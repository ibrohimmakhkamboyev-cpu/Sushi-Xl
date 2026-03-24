from __future__ import annotations

from typing import List, Optional

from pydantic import AliasChoices, BaseModel, ConfigDict, Field, field_validator, model_validator


class CategoryOut(BaseModel):
    id: int
    name: str
    description: Optional[str] = None
    isActive: bool = True
    sortOrder: int = 0


class ProductOut(BaseModel):
    id: int
    title: str
    description: Optional[str] = None
    imageUrl: Optional[str] = None
    categoryId: int
    categoryName: Optional[str] = None
    price: float
    oldPrice: Optional[float] = None
    isActive: bool = True
    isDrink: bool = False
    shortLabel: Optional[str] = None
    fullAddress: Optional[str] = None


class ProductListResponse(BaseModel):
    results: List[ProductOut]


class MenuCategoryOut(BaseModel):
    id: int
    name: str
    description: Optional[str] = None
    products: List[dict]


class MenuResponse(BaseModel):
    categories: List[dict]


class UserLoginIn(BaseModel):
    phone: str = Field(min_length=1, max_length=32)
    full_name: str = Field(min_length=1, max_length=120)
    preferred_lang: str = Field(default='ru', min_length=2, max_length=8)


class UserOtpRequestIn(BaseModel):
    phone: str = Field(min_length=7, max_length=32)
    full_name: Optional[str] = Field(default=None, max_length=120)
    preferred_lang: str = Field(default='ru', min_length=2, max_length=8)


class UserOtpVerifyIn(BaseModel):
    phone: str = Field(min_length=7, max_length=32)
    code: str = Field(min_length=4, max_length=12)
    full_name: Optional[str] = Field(default=None, max_length=120)
    preferred_lang: str = Field(default='ru', min_length=2, max_length=8)


class UserProfileUpdateIn(BaseModel):
    phone: str = Field(min_length=7, max_length=32)
    full_name: str = Field(
        min_length=1,
        max_length=120,
        validation_alias=AliasChoices('full_name', 'fullName'),
    )
    preferred_lang: str = Field(
        default='ru',
        min_length=2,
        max_length=8,
        validation_alias=AliasChoices('preferred_lang', 'preferredLang'),
    )

    model_config = ConfigDict(populate_by_name=True)


class UserLoginOut(BaseModel):
    user_id: int
    phone: str
    full_name: str
    preferred_lang: str


class AdminLoginIn(BaseModel):
    email: str = Field(min_length=5, max_length=255)
    password: str = Field(min_length=8, max_length=128)


class AdminTokenOut(BaseModel):
    access_token: str
    token_type: str = 'bearer'
    admin: dict


class CategoryCreateIn(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    description: Optional[str] = Field(default=None, max_length=400)
    nameEn: Optional[str] = Field(default=None, max_length=120)
    nameRu: Optional[str] = Field(default=None, max_length=120)
    nameUz: Optional[str] = Field(default=None, max_length=120)
    descriptionEn: Optional[str] = Field(default=None, max_length=400)
    descriptionRu: Optional[str] = Field(default=None, max_length=400)
    descriptionUz: Optional[str] = Field(default=None, max_length=400)
    isActive: bool = True
    sortOrder: int = 0


class CategoryUpdateIn(CategoryCreateIn):
    pass


class CategoryReorderIn(BaseModel):
    ids: List[int] = Field(min_length=1)


class ProductCreateIn(BaseModel):
    title: str = Field(min_length=1, max_length=160)
    description: Optional[str] = Field(default=None, max_length=1200)
    titleEn: Optional[str] = Field(default=None, max_length=160)
    titleRu: Optional[str] = Field(default=None, max_length=160)
    titleUz: Optional[str] = Field(default=None, max_length=160)
    descriptionEn: Optional[str] = Field(default=None, max_length=1200)
    descriptionRu: Optional[str] = Field(default=None, max_length=1200)
    descriptionUz: Optional[str] = Field(default=None, max_length=1200)
    imageUrl: Optional[str] = Field(default=None, max_length=1200)
    categoryId: int
    price: float = Field(ge=0)
    oldPrice: Optional[float] = Field(default=None, gt=0)
    discountStartAt: Optional[str] = Field(default=None, max_length=40)
    discountEndAt: Optional[str] = Field(default=None, max_length=40)
    sortOrder: int = 0
    isActive: bool = True
    isDrink: bool = False
    isRecommended: bool = False
    isPopular: bool = False
    isNew: bool = False

    @field_validator('oldPrice', mode='before')
    @classmethod
    def _normalize_old_price(cls, value: object) -> object:
        if value in (None, ''):
            return None
        try:
            parsed = float(value)
        except (TypeError, ValueError):
            return value
        return None if parsed <= 0 else parsed


class ProductUpdateIn(ProductCreateIn):
    pass


class ProductReorderIn(BaseModel):
    ids: List[int] = Field(min_length=1)


class AdminOrderUpdateIn(BaseModel):
    status: str = Field(min_length=2, max_length=64)
    paymentStatus: str = Field(alias='paymentStatus', min_length=2, max_length=64)

    model_config = ConfigDict(populate_by_name=True)


class AdminBannerIn(BaseModel):
    title: Optional[str] = Field(default=None, max_length=160)
    titleEn: str = Field(
        min_length=1,
        max_length=160,
        validation_alias=AliasChoices('titleEn', 'title_en'),
    )
    titleRu: str = Field(
        min_length=1,
        max_length=160,
        validation_alias=AliasChoices('titleRu', 'title_ru'),
    )
    titleUz: str = Field(
        min_length=1,
        max_length=160,
        validation_alias=AliasChoices('titleUz', 'title_uz'),
    )
    subtitle: Optional[str] = Field(default=None, max_length=300)
    subtitleEn: Optional[str] = Field(
        default=None,
        max_length=300,
        validation_alias=AliasChoices('subtitleEn', 'subtitle_en'),
    )
    subtitleRu: Optional[str] = Field(
        default=None,
        max_length=300,
        validation_alias=AliasChoices('subtitleRu', 'subtitle_ru'),
    )
    subtitleUz: Optional[str] = Field(
        default=None,
        max_length=300,
        validation_alias=AliasChoices('subtitleUz', 'subtitle_uz'),
    )
    imageUrl: str = Field(
        alias='imageUrl',
        validation_alias=AliasChoices('imageUrl', 'image_url'),
        min_length=1,
        max_length=1200,
    )
    actionType: str = Field(
        default='none',
        alias='actionType',
        validation_alias=AliasChoices('actionType', 'action_type'),
    )
    productId: Optional[int] = Field(
        default=None,
        alias='productId',
        validation_alias=AliasChoices('productId', 'product_id'),
    )
    categoryId: Optional[int] = Field(
        default=None,
        alias='categoryId',
        validation_alias=AliasChoices('categoryId', 'category_id'),
    )
    linkedProductIds: List[int] = Field(
        default_factory=list,
        alias='linkedProductIds',
        validation_alias=AliasChoices(
            'linkedProductIds',
            'linked_product_ids',
            'productIds',
            'product_ids',
        ),
    )
    targetUrl: Optional[str] = Field(
        default=None,
        alias='targetUrl',
        validation_alias=AliasChoices('targetUrl', 'target_url'),
        max_length=1200,
    )
    isActive: bool = Field(
        default=True,
        validation_alias=AliasChoices('isActive', 'is_active'),
    )
    sortOrder: int = Field(
        default=0,
        validation_alias=AliasChoices('sortOrder', 'sort_order'),
    )

    model_config = ConfigDict(populate_by_name=True)

    @field_validator('actionType')
    @classmethod
    def _normalize_action_type(cls, value: str) -> str:
        normalized = str(value or '').strip().lower()
        allowed = {
            'open_product',
            'open_products',
            'open_category',
            'open_discounts',
            'open_url',
            'none',
        }
        if normalized not in allowed:
            raise ValueError('Unsupported action type.')
        return normalized

    @field_validator('linkedProductIds', mode='before')
    @classmethod
    def _normalize_linked_product_ids(cls, value: object) -> List[int]:
        if value is None:
            return []
        raw_values: List[object]
        if isinstance(value, list):
            raw_values = value
        else:
            raw_values = [value]
        out: List[int] = []
        seen: set[int] = set()
        for item in raw_values:
            parsed: Optional[int] = None
            if isinstance(item, bool):
                parsed = None
            elif isinstance(item, (int, float)):
                parsed = int(item)
            elif isinstance(item, str):
                stripped = item.strip()
                if stripped.isdigit():
                    parsed = int(stripped)
            if parsed is None or parsed <= 0 or parsed in seen:
                continue
            seen.add(parsed)
            out.append(parsed)
        return out

    @model_validator(mode='after')
    def _validate_action_payload(self) -> 'AdminBannerIn':
        self.imageUrl = self.imageUrl.strip()
        self.title = (self.title or '').strip() or self.titleEn.strip()
        self.titleEn = self.titleEn.strip()
        self.titleRu = self.titleRu.strip()
        self.titleUz = self.titleUz.strip()
        self.subtitle = (self.subtitle or '').strip() or None
        self.subtitleEn = (self.subtitleEn or '').strip() or None
        self.subtitleRu = (self.subtitleRu or '').strip() or None
        self.subtitleUz = (self.subtitleUz or '').strip() or None
        self.targetUrl = (self.targetUrl or '').strip() or None

        if not self.imageUrl:
            raise ValueError('Banner image URL is required.')

        action = self.actionType
        if action == 'open_product':
            if self.productId is None or int(self.productId) <= 0:
                raise ValueError('open_product requires productId.')
            self.productId = int(self.productId)
            self.categoryId = None
            self.linkedProductIds = []
            self.targetUrl = None
            return self

        if action == 'open_products':
            if not self.linkedProductIds:
                raise ValueError('open_products requires linkedProductIds.')
            self.productId = None
            self.categoryId = None
            self.targetUrl = None
            return self

        if action == 'open_category':
            if self.categoryId is None or int(self.categoryId) <= 0:
                raise ValueError('open_category requires categoryId.')
            self.categoryId = int(self.categoryId)
            self.productId = None
            self.linkedProductIds = []
            self.targetUrl = None
            return self

        if action == 'open_discounts':
            self.productId = None
            self.categoryId = None
            self.linkedProductIds = []
            self.targetUrl = None
            return self

        if action == 'open_url':
            if not self.targetUrl:
                raise ValueError('open_url requires targetUrl.')
            self.productId = None
            self.categoryId = None
            self.linkedProductIds = []
            return self

        self.productId = None
        self.categoryId = None
        self.linkedProductIds = []
        self.targetUrl = None
        return self


class AdminNotificationIn(BaseModel):
    title: str = Field(default='', max_length=200)
    message: str = Field(default='', max_length=2000)
    titleEn: Optional[str] = Field(
        default=None,
        max_length=200,
        validation_alias=AliasChoices('titleEn', 'title_en'),
    )
    titleRu: Optional[str] = Field(
        default=None,
        max_length=200,
        validation_alias=AliasChoices('titleRu', 'title_ru'),
    )
    titleUz: Optional[str] = Field(
        default=None,
        max_length=200,
        validation_alias=AliasChoices('titleUz', 'title_uz'),
    )
    messageEn: Optional[str] = Field(
        default=None,
        max_length=2000,
        validation_alias=AliasChoices('messageEn', 'message_en'),
    )
    messageRu: Optional[str] = Field(
        default=None,
        max_length=2000,
        validation_alias=AliasChoices('messageRu', 'message_ru'),
    )
    messageUz: Optional[str] = Field(
        default=None,
        max_length=2000,
        validation_alias=AliasChoices('messageUz', 'message_uz'),
    )
    deliveryTypes: List[str] = Field(
        default_factory=lambda: ['in_app'],
        alias='deliveryTypes',
        validation_alias=AliasChoices('deliveryTypes', 'delivery_types'),
    )
    imageUrl: Optional[str] = Field(
        default=None,
        alias='imageUrl',
        validation_alias=AliasChoices('imageUrl', 'image_url'),
        max_length=1200,
    )
    type: str = Field(default='info', min_length=2, max_length=64)
    isActive: bool = Field(
        default=True,
        validation_alias=AliasChoices('isActive', 'active'),
    )

    model_config = ConfigDict(populate_by_name=True)

    @field_validator('deliveryTypes', mode='before')
    @classmethod
    def _normalize_delivery_types(cls, value: object) -> List[str]:
        if value is None:
            return ['in_app']
        if isinstance(value, str):
            out = [value]
        elif isinstance(value, list):
            out = [str(item) for item in value]
        else:
            out = [str(value)]
        allowed = {'push', 'in_app', 'mailing'}
        normalized: List[str] = []
        for raw in out:
            item = raw.strip().lower()
            if not item or item not in allowed:
                continue
            if item not in normalized:
                normalized.append(item)
        if not normalized:
            raise ValueError('At least one valid delivery type is required.')
        return normalized

    @model_validator(mode='after')
    def _validate_localized_content(self) -> 'AdminNotificationIn':
        titles = [
            self.title,
            self.titleEn or '',
            self.titleRu or '',
            self.titleUz or '',
        ]
        messages = [
            self.message,
            self.messageEn or '',
            self.messageRu or '',
            self.messageUz or '',
        ]
        has_title = any(str(value).strip() for value in titles)
        has_message = any(str(value).strip() for value in messages)
        if not has_title or not has_message:
            raise ValueError('At least one title and one message are required.')
        return self


class AdminFaqIn(BaseModel):
    question: str = Field(min_length=1, max_length=500)
    answer: str = Field(min_length=1, max_length=3000)
    questionEn: Optional[str] = Field(default=None, max_length=500)
    questionRu: Optional[str] = Field(default=None, max_length=500)
    questionUz: Optional[str] = Field(default=None, max_length=500)
    answerEn: Optional[str] = Field(default=None, max_length=3000)
    answerRu: Optional[str] = Field(default=None, max_length=3000)
    answerUz: Optional[str] = Field(default=None, max_length=3000)
    isActive: bool = True
    sortOrder: int = 0


class AdminSettingsIn(BaseModel):
    supportPhone: str = Field(alias='supportPhone', min_length=0, max_length=40)
    timezone: str = Field(min_length=3, max_length=80)
    currencyCode: str = Field(alias='currencyCode', min_length=3, max_length=12)
    callLabelEn: Optional[str] = Field(alias='callLabelEn', default=None, max_length=120)
    callLabelRu: Optional[str] = Field(alias='callLabelRu', default=None, max_length=120)
    callLabelUz: Optional[str] = Field(alias='callLabelUz', default=None, max_length=120)
    chatLabelEn: Optional[str] = Field(alias='chatLabelEn', default=None, max_length=120)
    chatLabelRu: Optional[str] = Field(alias='chatLabelRu', default=None, max_length=120)
    chatLabelUz: Optional[str] = Field(alias='chatLabelUz', default=None, max_length=120)
    chatSubtitleEn: Optional[str] = Field(alias='chatSubtitleEn', default=None, max_length=400)
    chatSubtitleRu: Optional[str] = Field(alias='chatSubtitleRu', default=None, max_length=400)
    chatSubtitleUz: Optional[str] = Field(alias='chatSubtitleUz', default=None, max_length=400)
    chatIntroEn: Optional[str] = Field(alias='chatIntroEn', default=None, max_length=1200)
    chatIntroRu: Optional[str] = Field(alias='chatIntroRu', default=None, max_length=1200)
    chatIntroUz: Optional[str] = Field(alias='chatIntroUz', default=None, max_length=1200)

    model_config = ConfigDict(populate_by_name=True)


class AdminUserIn(BaseModel):
    phone: str = Field(min_length=7, max_length=32)
    fullName: str = Field(alias='fullName', min_length=1, max_length=120)
    preferredLang: str = Field(alias='preferredLang', default='ru', min_length=2, max_length=8)

    model_config = ConfigDict(populate_by_name=True)


class AdminProfileUpdateIn(BaseModel):
    fullName: str = Field(alias='fullName', min_length=2, max_length=120)
    password: Optional[str] = Field(default=None, min_length=8, max_length=128)

    model_config = ConfigDict(populate_by_name=True)


class AddressIn(BaseModel):
    userId: int = Field(
        alias='userId',
        validation_alias=AliasChoices('userId', 'user_id'),
    )
    label: Optional[str] = None
    addressLine: str = Field(
        alias='addressLine',
        validation_alias=AliasChoices('addressLine', 'address_line'),
    )
    lat: Optional[float] = None
    lng: Optional[float] = None

    model_config = ConfigDict(populate_by_name=True)


class AddressOut(BaseModel):
    id: int
    userId: int
    label: Optional[str] = None
    addressLine: str
    lat: Optional[float] = None
    lng: Optional[float] = None


class OrderModifierIn(BaseModel):
    modifierId: int = Field(alias='modifier_id')
    price: float

    model_config = ConfigDict(populate_by_name=True)


class OrderItemIn(BaseModel):
    productId: Optional[int] = Field(default=None, alias='product_id')
    qty: int = Field(gt=0)
    price: float
    oldPrice: Optional[float] = Field(default=None, alias='old_price')
    title: Optional[str] = None
    modifiers: List[OrderModifierIn] = []

    model_config = ConfigDict(populate_by_name=True)


class OrderCreateIn(BaseModel):
    userId: int = Field(alias='user_id')
    items: List[OrderItemIn]
    deliveryType: str = Field(alias='delivery_type')
    addressId: Optional[int] = Field(default=None, alias='address_id')
    scheduledAt: Optional[str] = Field(default=None, alias='scheduled_at')
    notes: Optional[str] = None
    paymentMethod: str = Field(alias='payment_method')

    model_config = ConfigDict(populate_by_name=True)
