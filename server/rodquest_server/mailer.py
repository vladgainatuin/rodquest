"""Письма с кодом через SMTP (например, ящик на Яндекс Почте с паролем приложения).

Переменные окружения:
  SMTP_HOST (smtp.yandex.ru), SMTP_PORT (465), SMTP_USER, SMTP_PASSWORD, MAIL_FROM (= SMTP_USER)
"""

from __future__ import annotations

import os
import smtplib
import ssl
from email.message import EmailMessage

from .core import ApiError, Mailer

TEXTS = {
    "link": ("Родквест: подтверждение почты",
             "Код для привязки почты к вашей гильдии в Родквесте: {code}\n\n"
             "Код действует 15 минут. Если вы ничего не запрашивали — просто удалите это письмо."),
    "recover": ("Родквест: вход в гильдию",
                "Код для входа в вашу гильдию в Родквесте на новом устройстве: {code}\n\n"
                "Код действует 15 минут. Никому его не сообщайте. "
                "Если вы ничего не запрашивали — просто удалите это письмо."),
}


class SmtpMailer(Mailer):
    def __init__(self):
        self.host = os.environ.get("SMTP_HOST", "smtp.yandex.ru")
        self.port = int(os.environ.get("SMTP_PORT", "465"))
        self.user = os.environ.get("SMTP_USER", "")
        self.password = os.environ.get("SMTP_PASSWORD", "")
        self.sender = os.environ.get("MAIL_FROM", self.user)

    @property
    def configured(self) -> bool:
        return bool(self.user and self.password)

    def send_code(self, email, code, purpose):
        if not self.configured:
            raise ApiError(503, "mail_off", "Отправка писем не настроена на сервере")
        subject, text = TEXTS[purpose]
        msg = EmailMessage()
        msg["Subject"] = subject
        msg["From"] = f"Родквест <{self.sender}>"
        msg["To"] = email
        msg.set_content(text.format(code=code))
        try:
            with smtplib.SMTP_SSL(self.host, self.port, context=ssl.create_default_context(), timeout=8) as s:
                s.login(self.user, self.password)
                s.send_message(msg)
        except (OSError, smtplib.SMTPException) as e:
            print(f"mail error: {e!r}")
            raise ApiError(502, "mail_failed", "Не удалось отправить письмо, попробуйте позже")


class PrintMailer(Mailer):
    """Для локальной разработки: код печатается в консоль."""

    def send_code(self, email, code, purpose):
        print(f"[почта] {purpose} → {email}: код {code}")
