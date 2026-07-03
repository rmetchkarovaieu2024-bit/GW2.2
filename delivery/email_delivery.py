import os
import smtplib
from email.message import EmailMessage
from typing import List


def send(local_path: str, remote_filename: str, recipients: List[str]) -> str:
    """Emails local_path as an attachment to recipients. Returns a comma-joined
    string of recipients (mirrors sftp_delivery.upload's "remote path" return)."""
    host = os.environ["SMTP_HOST"]
    port = int(os.environ.get("SMTP_PORT", 587))
    username = os.environ.get("SMTP_USERNAME") or None
    password = os.environ.get("SMTP_PASSWORD") or None
    use_tls = os.environ.get("SMTP_USE_TLS", "true").lower() not in ("false", "0", "")
    from_addr = os.environ.get("EMAIL_FROM", username)

    msg = EmailMessage()
    msg["Subject"] = f"Export delivery: {remote_filename}"
    msg["From"] = from_addr
    msg["To"] = ", ".join(recipients)
    msg.set_content(f"Attached: {remote_filename}")

    with open(local_path, "rb") as f:
        msg.add_attachment(
            f.read(),
            maintype="application",
            subtype="octet-stream",
            filename=remote_filename,
        )

    with smtplib.SMTP(host, port) as smtp:
        if use_tls:
            smtp.starttls()
        if username:
            smtp.login(username, password)
        smtp.send_message(msg)

    return ", ".join(recipients)
