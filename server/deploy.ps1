# Родквест 0.8: развёртывание сервера синхронизации в Yandex Cloud.
#
# Что делает (повторный запуск безопасен — существующее не пересоздаётся):
#   1. сервисный аккаунт rodquest-sa с ролью ydb.editor;
#   2. база YDB serverless «rodquest»;
#   3. функция rodquest-api (Python 3.12), публичный HTTPS-адрес;
#   4. загружает код из этой папки и проверяет, что сервер отвечает;
#   5. записывает адрес сервера в ..\..\rodquest_server_url.txt (для сборки APK).
#
# Почта (необязательно): файл mail.txt рядом со скриптом, две строки:
#   SMTP_USER=rodquest@yandex.ru
#   SMTP_PASSWORD=пароль_приложения
param([string]$Log = "")

$ErrorActionPreference = "Continue"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
if ($Log -eq "") { $Log = Join-Path $here "deploy_log.txt" }

function Say($text) { Write-Host $text; Add-Content -Path $Log -Value $text -Encoding UTF8 }
function Fail($text) { Say "ОШИБКА: $text"; Say "===== FAILED ====="; exit 1 }

Set-Content -Path $Log -Value "===== Rodquest deploy $(Get-Date -Format s) =====" -Encoding UTF8

# --- yc ---
$yc = (Get-Command yc -ErrorAction SilentlyContinue).Source
if (-not $yc) {
    $cand = Join-Path $env:USERPROFILE "yandex-cloud\bin\yc.exe"
    if (Test-Path $cand) { $yc = $cand }
}
if (-not $yc) { Fail "не найден yc. Сначала запустите rodquest_cloud_setup.bat" }
Say "yc: $yc"

# Простые функции без param(): аргументы вида --flag уходят в yc как есть.
function YcRun($ycArgs) {
    $out = & $yc @ycArgs 2>&1
    $code = $LASTEXITCODE
    $text = ($out | ForEach-Object { "$_" }) -join "`n"
    Add-Content -Path $Log -Value "> yc $($ycArgs -join ' ')`n$text" -Encoding UTF8
    return @{ code = $code; text = $text }
}

function Yc {
    $a = @($args)
    $r = YcRun $a
    # yc 1.41: для некоторых сервисов не задан адрес API — повторяем с явным адресом и регионом.
    if ($r.code -ne 0 -and $r.text -match "endpoint should be set") {
        $r = YcRun ($a + @("--endpoint", "api.cloud.yandex.net:443"))
        if ($r.code -ne 0 -and $r.text -match "endpoint should be set") {
            $r = YcRun ($a + @("--region", "ru-central1"))
        }
    }
    return $r
}

function YcJson {
    $r = Yc @args --format json
    if ($r.code -ne 0) { return $null }
    # yc печатает прогресс («...1s...done (28s)») перед JSON — берём текст с первой { или [.
    $i = $r.text.IndexOfAny([char[]]@('{', '['))
    if ($i -lt 0) { return $null }
    $json = $r.text.Substring($i)
    try { return $json | ConvertFrom-Json } catch { return $null }
}

$folder = (Yc config get folder-id).text.Trim()
if (-not $folder -or $folder -match "ERROR|not set") { Fail "в yc не выбран каталог. Запустите rodquest_cloud_setup.bat ещё раз" }
Say "Каталог: $folder"

# --- 1. сервисный аккаунт ---
$sa = YcJson iam service-account get --name rodquest-sa
if (-not $sa) {
    Say "[1/5] Создаю сервисный аккаунт rodquest-sa..."
    $sa = YcJson iam service-account create --name rodquest-sa --description "Rodquest API"
    if (-not $sa) { Fail "не удалось создать сервисный аккаунт (см. deploy_log.txt)" }
} else { Say "[1/5] Сервисный аккаунт уже есть" }
$saId = $sa.id
$r = Yc resource-manager folder add-access-binding --id $folder --role ydb.editor --subject "serviceAccount:$saId"
if ($r.code -ne 0 -and $r.text -notmatch "already|AlreadyExists") { Say "Предупреждение: роль ydb.editor не выдана: $($r.text)" }

# --- 2. база YDB ---
$db = YcJson ydb database get --name rodquest
if (-not $db) {
    Say "[2/5] Создаю базу YDB serverless (1-3 минуты)..."
    $db = YcJson ydb database create --name rodquest --serverless --description "Rodquest family sync"
    if (-not $db) { Fail "не удалось создать базу YDB (см. deploy_log.txt). Проверьте, что привязан платёжный аккаунт" }
} else { Say "[2/5] База YDB уже есть" }
for ($i = 0; $i -lt 60 -and $db.status -ne "RUNNING"; $i++) {
    Start-Sleep -Seconds 5
    $db = YcJson ydb database get --name rodquest
}
if ($db.status -ne "RUNNING") { Fail "база YDB не запустилась (статус $($db.status))" }
if ($db.endpoint -notmatch '^(grpcs://[^/?]+)/?\?database=(.+)$') { Fail "непонятный адрес базы: $($db.endpoint)" }
$ydbEndpoint = $Matches[1]
$ydbDatabase = $Matches[2]
Say "База: $ydbEndpoint $ydbDatabase"

# --- 3. функция ---
$fn = YcJson serverless function get --name rodquest-api
if (-not $fn) {
    Say "[3/5] Создаю функцию rodquest-api..."
    $fn = YcJson serverless function create --name rodquest-api --description "Rodquest family sync API"
    if (-not $fn) { Fail "не удалось создать функцию (см. deploy_log.txt)" }
} else { Say "[3/5] Функция уже есть" }
$r = Yc serverless function allow-unauthenticated-invoke --name rodquest-api
if ($r.code -ne 0) { Say "Предупреждение: не удалось сделать функцию публичной: $($r.text)" }

# --- 4. код ---
Say "[4/5] Загружаю код сервера..."
$stage = Join-Path $env:TEMP "rodquest_server_stage"
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Path (Join-Path $stage "rodquest_server") | Out-Null
Copy-Item (Join-Path $here "index.py"), (Join-Path $here "requirements.txt") $stage
Copy-Item (Join-Path $here "rodquest_server\*.py") (Join-Path $stage "rodquest_server")

$envs = "YDB_ENDPOINT=$ydbEndpoint,YDB_DATABASE=$ydbDatabase"
$mail = Join-Path $here "mail.txt"
if (Test-Path $mail) {
    $vals = @{}
    foreach ($line in Get-Content $mail -Encoding UTF8) {
        if ($line -match '^\s*(SMTP_[A-Z]+|MAIL_FROM)\s*=\s*(.+?)\s*$') { $vals[$Matches[1]] = $Matches[2] }
    }
    foreach ($k in $vals.Keys) {
        if ($vals[$k] -match ',') { Fail "в mail.txt значение $k не должно содержать запятых" }
        $envs += ",$k=$($vals[$k])"
    }
    Say "Почта: $($vals['SMTP_USER'])"
} else { Say "Почта не настроена (нет mail.txt) — привязка почты будет недоступна" }

$r = Yc serverless function version create --function-name rodquest-api --runtime python312 `
    --entrypoint index.handler --memory 256MB --execution-timeout 15s --source-path $stage `
    --service-account-id $saId --environment $envs --metadata-options "gce-http-endpoint=enabled"
if ($r.code -ne 0) { Fail "не удалось загрузить версию функции (см. deploy_log.txt)" }

$fn = YcJson serverless function get --name rodquest-api
$url = "https://functions.yandexcloud.net/$($fn.id)"
Say "Адрес сервера: $url"
$urlFile = Join-Path (Split-Path -Parent (Split-Path -Parent $here)) "rodquest_server_url.txt"
Set-Content -Path $urlFile -Value $url -NoNewline -Encoding ASCII

# --- 5. проверка ---
Say "[5/5] Проверяю сервер..."
function Api($body, $token) {
    $h = @{ "Content-Type" = "application/json; charset=utf-8" }
    if ($token) { $h["X-Rodquest-Token"] = $token }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes(($body | ConvertTo-Json -Depth 6 -Compress))
    return Invoke-RestMethod -Method Post -Uri $url -Headers $h -Body $bytes -TimeoutSec 40
}
try {
    $p = $null
    # Публичный доступ к функции включается не мгновенно — до 2 минут ждём, пока 403 пропадёт.
    for ($i = 0; $i -lt 12 -and -not $p; $i++) {
        try { $p = Api @{ op = "ping" } } catch { Say "  попытка $($i + 1): $($_.Exception.Message)"; Start-Sleep -Seconds 10 }
    }
    if (-not $p.pong) { throw "ping не прошёл" }
    $g = Api @{ op = "create_guild"; name = "Проверка"; deviceName = "deploy"; heroIds = @("h1") }
    $push = Api @{ op = "push"; changes = @(@{ k = "goal/smoke"; d = '{"id":"smoke"}'; base = 0; s = "all" }) } $g.token
    $pull = Api @{ op = "pull"; since = 0 } $g.token
    if ($pull.changes.Count -ne 1) { throw "pull вернул $($pull.changes.Count) изменений вместо 1" }
    Api @{ op = "leave" } $g.token | Out-Null
    Say "Сервер работает: создание гильдии, запись и чтение — ОК (ревизия $($push.rev))"
} catch {
    Say "Проверка не прошла: $($_.Exception.Message)"
    try {
        $resp = $_.Exception.Response
        if ($resp) { Say "Ответ сервера: $((New-Object System.IO.StreamReader($resp.GetResponseStream())).ReadToEnd())" }
    } catch {}
    try {
        $logs = Yc serverless function logs --name rodquest-api --since 10m
        Say "Журнал функции:`n$($logs.text)"
    } catch {}
    Fail "сервер не отвечает как надо"
}
Say "===== DONE ====="
