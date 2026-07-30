"""注册所有 ORM 模型，确保 Base.metadata 能发现它们"""

from backend.app.models.character import Character
from backend.app.models.conversation import Conversation
from backend.app.models.message import Message
from backend.app.models.setting import Setting

__all__ = ["Character", "Conversation", "Message", "Setting"]
