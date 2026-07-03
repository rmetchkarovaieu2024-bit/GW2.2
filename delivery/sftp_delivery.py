import os
import posixpath
import paramiko


def upload(local_path: str, remote_filename: str) -> str:
    """Uploads local_path to SFTP_REMOTE_DIR/remote_filename. Returns the remote path."""
    host = os.environ["SFTP_HOST"]
    port = int(os.environ.get("SFTP_PORT", 22))
    username = os.environ["SFTP_USERNAME"]
    password = os.environ.get("SFTP_PASSWORD") or None
    key_path = os.environ.get("SFTP_PRIVATE_KEY_PATH") or None
    remote_dir = os.environ.get("SFTP_REMOTE_DIR", "/")

    transport = paramiko.Transport((host, port))
    try:
        if key_path:
            pkey = paramiko.RSAKey.from_private_key_file(key_path)
            transport.connect(username=username, pkey=pkey)
        else:
            transport.connect(username=username, password=password)

        sftp = paramiko.SFTPClient.from_transport(transport)
        try:
            remote_path = posixpath.join(remote_dir, remote_filename)
            sftp.put(local_path, remote_path)
            return remote_path
        finally:
            sftp.close()
    finally:
        transport.close()
