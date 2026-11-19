import 'package:meta/meta.dart';
/// `Shoplive.sendConversionEvent` 데이터. null 필드는 키를 생략한다.
class ShopliveConversionData {
  const ShopliveConversionData({this.type, this.products, this.orderId, this.referrer, this.custom});

  final String? type;
  final List<ShopliveConversionProduct>? products;
  final String? orderId;
  final String? referrer;
  final Map<String, Object?>? custom;

  @internal
  Map<String, Object?> toWire() => {
        if (type != null) 'type': type,
        if (products != null) 'products': [for (final p in products!) p.toWire()],
        if (orderId != null) 'orderId': orderId,
        if (referrer != null) 'referrer': referrer,
        if (custom != null) 'custom': custom,
      };
}

class ShopliveConversionProduct {
  const ShopliveConversionProduct({
    this.productId,
    this.customerProductId,
    this.sku,
    this.url,
    this.purchaseQuantity,
    this.purchaseUnitPrice,
  });

  final String? productId;
  final String? customerProductId;
  final String? sku;
  final String? url;
  final int? purchaseQuantity;
  final double? purchaseUnitPrice;

  @internal
  Map<String, Object?> toWire() => {
        if (productId != null) 'productId': productId,
        if (customerProductId != null) 'customerProductId': customerProductId,
        if (sku != null) 'sku': sku,
        if (url != null) 'url': url,
        if (purchaseQuantity != null) 'purchaseQuantity': purchaseQuantity,
        if (purchaseUnitPrice != null) 'purchaseUnitPrice': purchaseUnitPrice,
      };
}
