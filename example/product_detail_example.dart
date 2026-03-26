// Example: sealed state variants with riverpod_reducer.
//
// A product detail screen that transitions between Loading, Loaded, and Error
// states. Demonstrates how sealed class states compose cleanly with the
// reducer's exhaustive switch expression.

import 'package:riverpod/riverpod.dart';
import 'package:riverpod_reducer/riverpod_reducer.dart';

// --- State (sealed class with multiple variants) ---

sealed class ProductDetailState {}

class ProductLoading extends ProductDetailState {}

class ProductLoaded extends ProductDetailState {
  ProductLoaded({
    required this.name,
    required this.price,
    required this.isFavorite,
    required this.quantity,
  });

  final String name;
  final double price;
  final bool isFavorite;
  final int quantity;

  ProductLoaded copyWith({
    String? name,
    double? price,
    bool? isFavorite,
    int? quantity,
  }) => ProductLoaded(
    name: name ?? this.name,
    price: price ?? this.price,
    isFavorite: isFavorite ?? this.isFavorite,
    quantity: quantity ?? this.quantity,
  );

  @override
  String toString() =>
      'ProductLoaded($name, \$$price, fav=$isFavorite, qty=$quantity)';
}

class ProductError extends ProductDetailState {
  ProductError(this.message);
  final String message;

  @override
  String toString() => 'ProductError($message)';
}

// --- Events ---

sealed class ProductEvent {}

class ProductFetched extends ProductEvent {
  ProductFetched({required this.name, required this.price});
  final String name;
  final double price;
}

class ProductFetchFailed extends ProductEvent {
  ProductFetchFailed(this.message);
  final String message;
}

class FavoriteToggled extends ProductEvent {}

class QuantityIncremented extends ProductEvent {}

class QuantityDecremented extends ProductEvent {}

class ProductRefreshed extends ProductEvent {}

// --- External dependency: current user's favorites ---

final productDataProvider = FutureProvider.family<Map<String, dynamic>, String>(
  (ref, productId) async {
    // Simulate API call
    await Future<void>.delayed(Duration(milliseconds: 50));
    return {'name': 'Widget Pro', 'price': 29.99};
  },
);

// --- Notifier ---

class ProductDetailNotifier
    extends ReducerNotifier<ProductDetailState, ProductEvent> {
  ProductDetailNotifier(this.productId);
  final String productId;

  @override
  ProductDetailState initialState() => ProductLoading();

  @override
  void bindings() {
    // Bind to the async product data provider.
    // Loading/data/error phases map to typed events.
    bindAsync<Map<String, dynamic>>(
      productDataProvider(productId),
      (_, value) => switch (value) {
        AsyncData(:final value) => ProductFetched(
          name: value['name'] as String,
          price: value['price'] as double,
        ),
        AsyncError(:final error) => ProductFetchFailed(error.toString()),
        AsyncLoading() => null, // already showing loading from initialState
      },
    );
  }

  @override
  ProductDetailState reduce(ProductDetailState state, ProductEvent event) =>
      switch (event) {
        // Transitions FROM any state
        ProductFetched(:final name, :final price) => ProductLoaded(
          name: name,
          price: price,
          isFavorite: false,
          quantity: 1,
        ),
        ProductFetchFailed(:final message) => ProductError(message),
        ProductRefreshed() => ProductLoading(),

        // Transitions only valid in Loaded state — other states pass through
        FavoriteToggled() => switch (state) {
          ProductLoaded() => state.copyWith(isFavorite: !state.isFavorite),
          _ => state,
        },
        QuantityIncremented() => switch (state) {
          ProductLoaded() => state.copyWith(quantity: state.quantity + 1),
          _ => state,
        },
        QuantityDecremented() => switch (state) {
          ProductLoaded() when state.quantity > 1 => state.copyWith(
            quantity: state.quantity - 1,
          ),
          _ => state,
        },
      };

  /// Side effect: refresh the product data.
  void refresh() {
    dispatch(ProductRefreshed());
    ref.invalidate(productDataProvider(productId));
    // bindAsync will fire again when the provider re-resolves
  }
}

final productDetailProvider =
    NotifierProvider.family<ProductDetailNotifier, ProductDetailState, String>(
      ProductDetailNotifier.new,
    );

// --- Usage ---

void main() async {
  final container = ProviderContainer();
  const productId = 'abc-123';

  // Initially loading
  print(container.read(productDetailProvider(productId)));
  // => ProductLoading

  // Wait for the future to resolve
  await Future<void>.delayed(Duration(milliseconds: 100));
  print(container.read(productDetailProvider(productId)));
  // => ProductLoaded(Widget Pro, $29.99, fav=false, qty=1)

  // User interactions — only affect Loaded state
  final notifier = container.read(productDetailProvider(productId).notifier);

  notifier.dispatch(FavoriteToggled());
  print(container.read(productDetailProvider(productId)));
  // => ProductLoaded(Widget Pro, $29.99, fav=true, qty=1)

  notifier.dispatch(QuantityIncremented());
  notifier.dispatch(QuantityIncremented());
  print(container.read(productDetailProvider(productId)));
  // => ProductLoaded(Widget Pro, $29.99, fav=true, qty=3)

  notifier.dispatch(QuantityDecremented());
  print(container.read(productDetailProvider(productId)));
  // => ProductLoaded(Widget Pro, $29.99, fav=true, qty=2)

  // Test reduce in isolation — no framework needed
  final testNotifier = ProductDetailNotifier('test');
  final loaded = ProductLoaded(
    name: 'Test',
    price: 9.99,
    isFavorite: false,
    quantity: 1,
  );

  // Favorite toggle on Loaded state
  final toggled = testNotifier.reduce(loaded, FavoriteToggled());
  assert(toggled is ProductLoaded && toggled.isFavorite == true);

  // Favorite toggle on Loading state — no-op
  final noOp = testNotifier.reduce(ProductLoading(), FavoriteToggled());
  assert(noOp is ProductLoading);

  // Quantity can't go below 1
  final atMin = testNotifier.reduce(loaded, QuantityDecremented());
  assert(atMin is ProductLoaded && atMin.quantity == 1);

  print('All assertions passed!');

  container.dispose();
}
