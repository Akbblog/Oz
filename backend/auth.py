"""
Authentication utilities
"""
import logging
from passlib.context import CryptContext
from jose import JWTError, jwt
from datetime import datetime, timedelta
from typing import Optional
import os

import config  # loads backend/.env before SECRET_KEY is read (audit M-10)

# passlib 1.7.x logs a noisy (but harmless) warning with bcrypt 4.x about version metadata.
# Suppress it to keep production logs clean.
logging.getLogger("passlib.handlers.bcrypt").setLevel(logging.ERROR)

pwd_context = CryptContext(schemes=["bcrypt", "pbkdf2_sha256"], deprecated="auto")
_PLACEHOLDER_KEYS = {"", "your-secret-key-change-in-production", "a_secure_secret_key", "change-me"}
SECRET_KEY = os.getenv("SECRET_KEY", "")
if SECRET_KEY in _PLACEHOLDER_KEYS or len(SECRET_KEY) < 16:
    # A public/empty signing key lets anyone forge a token for any user
    # (CLAUDE_DEEP_AUDIT M-10). Refuse to start instead of falling back.
    raise RuntimeError(
        "SECRET_KEY is missing, too short (<16 chars) or a known placeholder. "
        "Set a long random SECRET_KEY in backend/.env."
    )
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 60 * 24 * 7  # 7 days

def verify_password(plain_password: str, hashed_password: str) -> bool:
    """Verify a password against a hash"""
    return pwd_context.verify(plain_password, hashed_password)

def get_password_hash(password: str) -> str:
    """Hash a password"""
    return pwd_context.hash(password)

def create_access_token(data: dict, expires_delta: Optional[timedelta] = None):
    """Create JWT access token"""
    to_encode = data.copy()
    if expires_delta:
        expire = datetime.utcnow() + expires_delta
    else:
        expire = datetime.utcnow() + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    # iat lets the server reject tokens issued before a password change.
    to_encode.update({"exp": expire, "iat": datetime.utcnow()})
    encoded_jwt = jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)
    return encoded_jwt

def decode_access_token(token: str) -> Optional[dict]:
    """Decode JWT token"""
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        return payload
    except JWTError:
        return None
