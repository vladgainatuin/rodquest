# Родквест 0.8: веб-версия в Yandex Object Storage (сайт из бакета).
#
# Что делает (повторный запуск безопасен):
#   1. бакет rodquest-web-<каталог> с публичным чтением;
#   2. включает в нём хостинг сайта (index.html);
#   3. загружает ..\build\web с правильными типами файлов;
#   4. проверяет, что сайт открывается, и пишет адрес в ..\..\rodquest_web_url.txt.
param([string]$Log = "")

$ErrorActionPreference = "Continue"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$project = Split-Path -Parent $here
if ($Log -eq "") { $Log = Join-Path $here "web_deploy_log.txt" }

function Say($text) { Write-Host $text; Add-Content -Path $Log -Value $text -Encoding UTF8 }
function Fail($text) { Say "ОШИБКА: $text"; Say "===== FAILED ====="; exit 1 }

Say "===== Rodquest web deploy $(Get-Date -Format s) ====="

$yc = (Get-Command yc -ErrorAction SilentlyContinue).Source
if (-not $yc) {
    $cand = Join-Path $env:USERPROFILE "yandex-cloud\bin\yc.exe"
    if (Test-Path $cand) { $yc = $cand }
}
if (-not $yc) { Fail "не найден yc" }

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
    if ($r.code -ne 0 -and $r.text -match "endpoint should be set") {
        $r = YcRun ($a + @("--endpoint", "api.cloud.yandex.net:443"))
    }
    return $r
}

$web = Join-Path $project "build\web"
if (-not (Test-Path (Join-Path $web "index.html"))) { Fail "нет собранного сайта в build\web" }

$folder = (Yc config get folder-id).text.Trim()
if (-not $folder -or $folder -match "ERROR|not set") { Fail "в yc не выбран каталог" }
$bucket = "rodquest-web-$($folder.ToLower())"
Say "Бакет: $bucket"

# --- 1. бакет ---
$r = Yc storage bucket get --name $bucket
if ($r.code -ne 0) {
    Say "[1/4] Создаю бакет..."
    $r = Yc storage bucket create --name $bucket --default-storage-class standard --max-size 1073741824 --public-read
    if ($r.code -ne 0) { Fail "не удалось создать бакет (см. журнал)" }
} else {
    Say "[1/4] Бакет уже есть"
    $r = Yc storage bucket update --name $bucket --public-read
}

# --- 2. хостинг сайта ---
Say "[2/4] Включаю хостинг сайта..."
# yc ждёт настройки сайта в JSON.
$ws = Join-Path $env:TEMP "rodquest_website.json"
Set-Content -Path $ws -Value '{"index": "index.html", "error": "index.html"}' -Encoding ASCII
$r = Yc storage bucket update --name $bucket --website-settings-from-file $ws
if ($r.code -ne 0) { Fail "не удалось включить хостинг сайта (см. журнал)" }

# --- 3. файлы ---
$types = @{
    ".html" = "text/html; charset=utf-8"; ".js" = "text/javascript; charset=utf-8"; ".mjs" = "text/javascript; charset=utf-8"
    ".json" = "application/json; charset=utf-8"; ".wasm" = "application/wasm"; ".png" = "image/png"
    ".jpg" = "image/jpeg"; ".svg" = "image/svg+xml"; ".ico" = "image/x-icon"; ".webp" = "image/webp"
    ".ttf" = "font/ttf"; ".otf" = "font/otf"; ".woff2" = "font/woff2"; ".css" = "text/css; charset=utf-8"
    ".txt" = "text/plain; charset=utf-8"; ".frag" = "text/plain; charset=utf-8"; ".symbols" = "text/plain; charset=utf-8"
}
# Эти файлы меняются при каждой сборке — браузер должен всегда брать свежие.
$noCache = @("index.html", "flutter_bootstrap.js", "flutter_service_worker.js", "version.json", "manifest.json", "main.dart.js")

$files = Get-ChildItem -Path $web -Recurse -File
Say "[3/4] Загружаю файлы сайта: $($files.Count) шт..."
$n = 0
foreach ($f in $files) {
    $key = $f.FullName.Substring($web.Length + 1).Replace("\", "/")
    $type = $types[$f.Extension.ToLower()]
    if (-not $type) { $type = "application/octet-stream" }
    if ($key -eq "assets/NOTICES") { $type = "text/plain; charset=utf-8" }
    $cache = if ($noCache -contains $key) { "no-cache" } else { "max-age=3600" }
    $ok = $false
    for ($t = 1; $t -le 3 -and -not $ok; $t++) {
        $r = Yc storage s3api put-object --bucket $bucket --key $key --body $f.FullName --content-type $type --cache-control $cache
        if ($r.code -ne 0 -and $r.text -match "unknown (command|flag)") {
            $r = Yc storage s3 cp $f.FullName "s3://$bucket/$key" --content-type $type --cache-control $cache
        }
        $ok = ($r.code -eq 0)
        if (-not $ok) { Start-Sleep -Seconds 3 }
    }
    if (-not $ok) { Fail "не удалось загрузить $key (см. журнал)" }
    $n++
    if ($n % 10 -eq 0) { Say "  загружено $n из $($files.Count)" }
}
Say "  загружено $n из $($files.Count)"

# --- 4. проверка ---
$url = "https://$bucket.website.yandexcloud.net/"
Say "[4/4] Проверяю сайт: $url"
$okSite = $false
for ($i = 0; $i -lt 6 -and -not $okSite; $i++) {
    try {
        $resp = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 30
        if ($resp.StatusCode -eq 200 -and $resp.Content -match "flutter") { $okSite = $true }
    } catch { Say "  попытка $($i + 1): $($_.Exception.Message)"; Start-Sleep -Seconds 10 }
}
if (-not $okSite) { Fail "сайт не открылся по адресу $url" }

$urlFile = Join-Path (Split-Path -Parent $project) "rodquest_web_url.txt"
Set-Content -Path $urlFile -Value $url -NoNewline -Encoding ASCII
Say "Сайт работает: $url"
Say "===== DONE ====="
