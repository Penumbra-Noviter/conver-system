"""
Mod 库与角色挂载 REST API 路由（MD-2 / 01）

包含：
    - GET    /api/mods                             — 全局 Mod 库列表（id 升序）
    - POST   /api/mods                             — 创建 Mod
    - PUT    /api/mods/{mod_id}                    — 部分更新 Mod
    - DELETE /api/mods/{mod_id}                    — 删除 Mod（204，级联删绑定）
    - GET    /api/characters/{character_id}/mods   — 角色挂载列表（sort_order 升序）
    - POST   /api/characters/{character_id}/mods   — 挂载 Mod 到角色
    - PUT    /api/characters/{character_id}/mods/order — 原子批量重排挂载顺序
    - PUT    /api/mod-bindings/{binding_id}        — 切换启用开关
    - PUT    /api/mod-bindings/{binding_id}/sort   — 调整排序
    - DELETE /api/mod-bindings/{binding_id}        — 解绑（204）

路由层只做 HTTP 映射：守卫（角色/Mod/绑定不存在）与重复绑定由服务层抛领域异常
（CharacterNotFoundError / ModNotFoundError / ModBindingNotFoundError /
ModAlreadyBoundError），经统一 exception handler 转 404/400；批量重排的参数非法
（空列表 / 未恰好覆盖）由服务层 ModReorderError 转 400；请求体校验（target_area
越 Literal、字段类型、重复 binding_id）由 Pydantic Schema 在进入服务层前拦截（422）。
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, Response, status
from sqlalchemy.orm import Session

from backend.app.database import get_db
from backend.app.schemas.mods import (
    ModBindCreate,
    ModBindSortUpdate,
    ModBindingResponse,
    ModBindingUpdate,
    ModCreate,
    ModResponse,
    ModsOrderUpdate,
    ModUpdate,
)
from backend.app.services import character as character_service
from backend.app.services import mods as mods_service

router = APIRouter(tags=["Mod"])


@router.get("/api/mods", response_model=list[ModResponse])
def list_mods(db: Session = Depends(get_db)) -> list[ModResponse]:
    """获取全局 Mod 库列表（id 升序，确定性）"""
    return mods_service.list_mods(db)


@router.post("/api/mods", response_model=ModResponse)
def create_mod(payload: ModCreate, db: Session = Depends(get_db)) -> ModResponse:
    """创建 Mod（非法请求体 → 422）"""
    return mods_service.create_mod(db, payload)


@router.put("/api/mods/{mod_id}", response_model=ModResponse)
def update_mod(
    mod_id: int, payload: ModUpdate, db: Session = Depends(get_db)
) -> ModResponse:
    """部分更新 Mod（仅提交显式字段；Mod 不存在 → 404）"""
    return mods_service.update_mod(db, mod_id, payload)


@router.delete("/api/mods/{mod_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_mod(mod_id: int, db: Session = Depends(get_db)) -> Response:
    """删除 Mod（级联删绑定；Mod 不存在 → 404）"""
    mods_service.delete_mod(db, mod_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get(
    "/api/characters/{character_id}/mods",
    response_model=list[ModBindingResponse],
)
def list_character_mods(
    character_id: int, db: Session = Depends(get_db)
) -> list[ModBindingResponse]:
    """获取角色已挂载绑定列表（sort_order 升序、同序按 mod_id 稳定；角色不存在 → 404）"""
    character_service.require_character(db, character_id)
    return mods_service.list_character_mods(db, character_id)


@router.put(
    "/api/characters/{character_id}/mods/order",
    response_model=list[ModBindingResponse],
)
def reorder_character_mods(
    character_id: int, payload: ModsOrderUpdate, db: Session = Depends(get_db)
) -> list[ModBindingResponse]:
    """原子批量重排角色挂载 Mod 顺序（空列表 → 400；角色不存在/归属不符/缺失 → 404）"""
    return mods_service.reorder_character_mods(db, character_id, payload.root)


@router.post(
    "/api/characters/{character_id}/mods",
    response_model=ModBindingResponse,
)
def bind_mod(
    character_id: int, payload: ModBindCreate, db: Session = Depends(get_db)
) -> ModBindingResponse:
    """挂载 Mod 到角色（角色/Mod 不存在 → 404；重复挂载 → 400）"""
    return mods_service.bind_mod(
        db,
        character_id,
        payload.mod_id,
        enabled=payload.enabled,
        sort_order=payload.sort_order,
    )


@router.put("/api/mod-bindings/{binding_id}", response_model=ModBindingResponse)
def update_binding_enabled(
    binding_id: int, payload: ModBindingUpdate, db: Session = Depends(get_db)
) -> ModBindingResponse:
    """切换绑定开关（绑定不存在 → 404）"""
    return mods_service.set_binding_enabled(db, binding_id, payload.enabled)


@router.put(
    "/api/mod-bindings/{binding_id}/sort",
    response_model=ModBindingResponse,
)
def update_binding_sort(
    binding_id: int, payload: ModBindSortUpdate, db: Session = Depends(get_db)
) -> ModBindingResponse:
    """调整绑定排序（绑定不存在 → 404）"""
    return mods_service.set_binding_sort_order(db, binding_id, payload.sort_order)


@router.delete("/api/mod-bindings/{binding_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_binding(binding_id: int, db: Session = Depends(get_db)) -> Response:
    """解绑（删除绑定行；绑定不存在 → 404）"""
    mods_service.unbind_mod(db, binding_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
