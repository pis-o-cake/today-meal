"""아직 구현하지 않은 엔드포인트.

빈 성공 응답을 돌려주면 앱이 동작한다고 착각한다. 501 과 담당 슬라이스를 함께 돌려주어
무엇이 남았는지 드러낸다.
"""

from fastapi import HTTPException, status


def not_implemented(slice_id: str, feature_id: str) -> HTTPException:
    """구현 예정 응답을 만든다.

    Args:
        slice_id: 이 엔드포인트를 구현할 슬라이스. 예 `S-02`.
        feature_id: 대응 기능 ID. 예 `F-04`.
    """
    return HTTPException(
        status_code=status.HTTP_501_NOT_IMPLEMENTED,
        detail=f"Not implemented yet: planned in slice {slice_id} for feature {feature_id}",
    )
