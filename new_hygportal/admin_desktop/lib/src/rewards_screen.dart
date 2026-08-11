part of '../main.dart';

class RewardsHeader extends StatelessWidget {
  const RewardsHeader({required this.onAddReward, super.key});
  final VoidCallback onAddReward;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(
            Icons.emoji_events_outlined,
            color: HygColors.goldStrong,
            size: 42,
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Rewards',
                  style: TextStyle(
                    fontFamily: HygTypography.headingFontFamily,
                    fontFamilyFallback: HygTypography.headingFallbacks,
                    color: HygColors.ink,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Recognize and reward users with redeemable points and incentives.',
                  style: TextStyle(
                    fontFamily: HygTypography.bodyFontFamily,
                    fontFamilyFallback: HygTypography.fontFallbacks,
                    color: Color(0xFF64748B),
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: HygColors.gold,
              foregroundColor: HygColors.ink,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: onAddReward,
            icon: const Icon(Icons.add, size: 19, color: HygColors.ink),
            label: const Text(
              'Add Reward',
              style: TextStyle(
                fontFamily: HygTypography.bodyFontFamily,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: HygColors.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class RewardsSearchBar extends StatelessWidget {
  const RewardsSearchBar({
    required this.controller,
    this.onChanged,
    super.key,
  });

  final TextEditingController controller;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: const TextStyle(
          fontFamily: HygTypography.bodyFontFamily,
          fontSize: 14,
          color: Color(0xFF1E293B),
        ),
        decoration: const InputDecoration(
          hintText: 'Search reward or product name',
          hintStyle: TextStyle(
            fontFamily: HygTypography.bodyFontFamily,
            fontSize: 14,
            color: Color(0xFF94A3B8),
            fontWeight: FontWeight.w400,
          ),
          prefixIcon: Padding(
            padding: EdgeInsets.only(left: 14, right: 10),
            child: Icon(
              Icons.search,
              color: Color(0xFF94A3B8),
              size: 20,
            ),
          ),
          prefixIconConstraints: BoxConstraints(
            minWidth: 44,
            minHeight: 44,
          ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }
}

class RewardItem {
  RewardItem({
    required this.id,
    required this.productName,
    required this.stocks,
    required this.pointsValue,
    this.status = 'Active',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String id;
  String productName;
  int stocks;
  int pointsValue;
  String status;
  final DateTime createdAt;
}

class RewardsPanel extends StatelessWidget {
  const RewardsPanel({
    required this.rewards,
    required this.searchQuery,
    required this.onEditReward,
    required this.onDeleteReward,
    super.key,
  });

  final List<RewardItem> rewards;
  final String searchQuery;
  final ValueChanged<RewardItem> onEditReward;
  final ValueChanged<RewardItem> onDeleteReward;

  @override
  Widget build(BuildContext context) {
    final filtered = rewards.where((r) {
      if (searchQuery.trim().isEmpty) return true;
      return r.productName.toLowerCase().contains(searchQuery.toLowerCase().trim());
    }).toList();

    if (rewards.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: Color(0xFFFEF3C7),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.emoji_events_outlined,
                color: HygColors.goldStrong,
                size: 32,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'No Rewards Added Yet',
              style: TextStyle(
                fontFamily: HygTypography.headingFontFamily,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: HygColors.ink,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Create your first reward item or incentive for employee recognition.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: HygTypography.bodyFontFamily,
                fontSize: 13,
                color: Color(0xFF64748B),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Reward Items (${filtered.length})',
                style: const TextStyle(
                  fontFamily: HygTypography.headingFontFamily,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0F172A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const _RewardsTableHeader(),
          const SizedBox(height: 8),
          if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 36),
              child: Center(
                child: Text(
                  'No rewards matching "$searchQuery"',
                  style: const TextStyle(
                    fontFamily: HygTypography.bodyFontFamily,
                    color: Color(0xFF64748B),
                    fontSize: 14,
                  ),
                ),
              ),
            )
          else
            ...filtered.map(
              (item) => _RewardRow(
                reward: item,
                onEdit: () => onEditReward(item),
                onDelete: () => onDeleteReward(item),
              ),
            ),
        ],
      ),
    );
  }
}

class _RewardsTableHeader extends StatelessWidget {
  const _RewardsTableHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: HygColors.background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Row(
        children: [
          Expanded(flex: 4, child: HeaderLabel('PRODUCT / ITEM NAME')),
          Expanded(flex: 2, child: HeaderLabel('STOCKS')),
          Expanded(flex: 2, child: HeaderLabel('POINTS VALUE')),
          Expanded(flex: 2, child: HeaderLabel('STATUS')),
          SizedBox(
            width: 88,
            child: Align(
              alignment: Alignment.centerRight,
              child: HeaderLabel('ACTIONS'),
            ),
          ),
        ],
      ),
    );
  }
}

class _RewardRow extends StatelessWidget {
  const _RewardRow({
    required this.reward,
    required this.onEdit,
    required this.onDelete,
  });

  final RewardItem reward;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final isOut = reward.stocks <= 0;
    final isActive = reward.status == 'Active';

    return Container(
      height: 56,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: HygColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(
                    Icons.card_giftcard,
                    color: HygColors.goldStrong,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    reward.productName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: HygTypography.bodyFontFamily,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isOut ? const Color(0xFFFEF2F2) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    isOut ? 'Out of Stock' : '${reward.stocks} pcs',
                    style: TextStyle(
                      fontFamily: HygTypography.bodyFontFamily,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isOut ? const Color(0xFFDC2626) : const Color(0xFF334155),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFFDE68A)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.stars,
                        size: 14,
                        color: Color(0xFFD97706),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${reward.pointsValue} PTS',
                        style: const TextStyle(
                          fontFamily: HygTypography.bodyFontFamily,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFB45309),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isActive ? const Color(0xFFDCFCE7) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    reward.status,
                    style: TextStyle(
                      fontFamily: HygTypography.bodyFontFamily,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isActive ? const Color(0xFF15803D) : const Color(0xFF64748B),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 88,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: 'Edit reward',
                  onPressed: onEdit,
                  icon: const Icon(
                    Icons.edit_outlined,
                    color: Color(0xFF2563EB),
                    size: 18,
                  ),
                ),
                IconButton(
                  tooltip: 'Delete reward',
                  onPressed: onDelete,
                  icon: const Icon(
                    Icons.delete_outline,
                    color: Color(0xFFDC2626),
                    size: 18,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AddRewardDialog extends StatefulWidget {
  const AddRewardDialog({this.reward, super.key});

  final RewardItem? reward;

  @override
  State<AddRewardDialog> createState() => _AddRewardDialogState();
}

class _AddRewardDialogState extends State<AddRewardDialog> {
  final _stocksController = TextEditingController();
  final _pointsValueController = TextEditingController();
  String _selectedProduct = 'Select product';
  List<InventoryProductItem> _inventoryProducts = [];
  bool _isLoadingProducts = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    final r = widget.reward;
    if (r != null) {
      _selectedProduct = r.productName;
      _stocksController.text = r.stocks.toString();
      _pointsValueController.text = r.pointsValue.toString();
    }
    _loadInventoryProducts();
  }

  Future<void> _loadInventoryProducts() async {
    try {
      final products = await InventoryProductsService.fetchStoreInventory();
      if (!mounted) return;
      setState(() {
        _inventoryProducts = products;
        _isLoadingProducts = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingProducts = false;
        _error = 'Unable to load store inventory.';
      });
    }
  }

  @override
  void dispose() {
    _stocksController.dispose();
    _pointsValueController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_selectedProduct == 'Select product') {
      setState(() => _error = 'Please select a product.');
      return;
    }
    final stocks = int.tryParse(_stocksController.text.trim());
    if (stocks == null) {
      setState(() => _error = 'Please enter a valid stocks number.');
      return;
    }
    final points = int.tryParse(_pointsValueController.text.trim());
    if (points == null) {
      setState(() => _error = 'Please enter a valid points value.');
      return;
    }

    setState(() => _error = null);

    try {
      RewardItem? result;
      if (widget.reward == null) {
        result = await RewardService.createReward(
          productName: _selectedProduct,
          stocks: stocks,
          pointsValue: points,
        );
      } else {
        result = await RewardService.updateReward(
          id: widget.reward!.id,
          productName: _selectedProduct,
          stocks: stocks,
          pointsValue: points,
          status: widget.reward!.status,
        );
      }

      if (!mounted) return;
      if (result != null) {
        Navigator.of(context).pop(result);
        return;
      }
    } catch (_) {}

    if (!mounted) return;
    final fallbackItem = RewardItem(
      id: widget.reward?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      productName: _selectedProduct,
      stocks: stocks,
      pointsValue: points,
      status: widget.reward?.status ?? 'Active',
    );
    Navigator.of(context).pop(fallbackItem);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        width: 440,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.emoji_events_outlined,
                    color: HygColors.goldStrong,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  widget.reward != null ? 'Edit Reward' : 'Add Reward',
                  style: const TextStyle(
                    fontFamily: HygTypography.headingFontFamily,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const Spacer(),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: const Icon(
                    Icons.close,
                    color: Color(0xFF334155),
                    size: 20,
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(color: Color(0xFFE2E8F0), height: 1),
            const SizedBox(height: 20),
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFCA5A5)),
                ),
                child: Text(
                  _error!,
                  style: const TextStyle(
                    color: Color(0xFFDC2626),
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(height: 14),
            ],
            const Text(
              'Product Name',
              style: TextStyle(
                fontFamily: HygTypography.bodyFontFamily,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFF475569),
              ),
            ),
            const SizedBox(height: 8),
            SearchableProductDropdown(
              products: _inventoryProducts,
              isLoading: _isLoadingProducts,
              onSelected: (selected) {
                setState(() {
                  _selectedProduct = selected.itemName;
                  final pointsVal = selected.price.round();
                  _pointsValueController.text = pointsVal.toString();
                  _error = null;
                });
              },
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Stocks',
                        style: TextStyle(
                          fontFamily: HygTypography.bodyFontFamily,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF475569),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _stocksController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: InputDecoration(
                          hintText: '0',
                          hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: HygColors.goldStrong),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Points Value',
                        style: TextStyle(
                          fontFamily: HygTypography.bodyFontFamily,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF475569),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _pointsValueController,
                        readOnly: true,
                        decoration: InputDecoration(
                          hintText: '0',
                          hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          filled: true,
                          fillColor: const Color(0xFFF1F5F9),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    backgroundColor: const Color(0xFFE2E8F0),
                    foregroundColor: const Color(0xFF334155),
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(
                      fontFamily: HygTypography.bodyFontFamily,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF334155),
                    ),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: HygColors.gold,
                    foregroundColor: HygColors.ink,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: _submit,
                  child: Text(
                    widget.reward != null ? 'Update Reward' : 'Add Reward',
                    style: const TextStyle(
                      fontFamily: HygTypography.bodyFontFamily,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: HygColors.ink,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class SearchableProductDropdown extends StatefulWidget {
  const SearchableProductDropdown({
    required this.products,
    required this.isLoading,
    required this.onSelected,
    super.key,
  });

  final List<InventoryProductItem> products;
  final bool isLoading;
  final ValueChanged<InventoryProductItem> onSelected;

  @override
  State<SearchableProductDropdown> createState() =>
      _SearchableProductDropdownState();
}

class _SearchableProductDropdownState
    extends State<SearchableProductDropdown> {
  final _searchController = TextEditingController();
  final _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  bool _isOpen = false;
  String _selectedTitle = 'Select product';

  @override
  void dispose() {
    _closeDropdown();
    _searchController.dispose();
    super.dispose();
  }

  void _toggleDropdown() {
    if (_isOpen) {
      _closeDropdown();
    } else {
      _openDropdown();
    }
  }

  void _openDropdown() {
    if (widget.isLoading) return;
    _overlayEntry = _createOverlayEntry();
    Overlay.of(context).insert(_overlayEntry!);
    setState(() => _isOpen = true);
  }

  void _closeDropdown() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    if (mounted && _isOpen) {
      setState(() => _isOpen = false);
    }
  }

  OverlayEntry _createOverlayEntry() {
    final renderBox = context.findRenderObject() as RenderBox;
    final size = renderBox.size;

    return OverlayEntry(
      builder: (context) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _closeDropdown,
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            width: size.width,
            child: CompositedTransformFollower(
              link: _layerLink,
              showWhenUnlinked: false,
              offset: Offset(0, size.height + 4),
              child: Material(
                elevation: 8,
                shadowColor: Colors.black26,
                borderRadius: BorderRadius.circular(8),
                color: Colors.white,
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 240),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFCBD5E1)),
                  ),
                  child: _DropdownListContent(
                    products: widget.products,
                    searchController: _searchController,
                    onSelect: (item) {
                      setState(() {
                        _selectedTitle = item.itemName;
                      });
                      widget.onSelected(item);
                      _closeDropdown();
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: InkWell(
        onTap: _toggleDropdown,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _isOpen ? HygColors.goldStrong : const Color(0xFFCBD5E1),
              width: _isOpen ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _selectedTitle,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: HygTypography.bodyFontFamily,
                    fontSize: 14,
                    color: _selectedTitle == 'Select product'
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF1E293B),
                  ),
                ),
              ),
              widget.isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      _isOpen ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                      color: const Color(0xFF64748B),
                      size: 20,
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DropdownListContent extends StatefulWidget {
  const _DropdownListContent({
    required this.products,
    required this.searchController,
    required this.onSelect,
  });

  final List<InventoryProductItem> products;
  final TextEditingController searchController;
  final ValueChanged<InventoryProductItem> onSelect;

  @override
  State<_DropdownListContent> createState() => _DropdownListContentState();
}

class _DropdownListContentState extends State<_DropdownListContent> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.products.where((p) {
      if (_query.trim().isEmpty) return true;
      return p.itemName.toLowerCase().contains(_query.toLowerCase().trim());
    }).toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: SizedBox(
            height: 36,
            child: TextField(
              controller: widget.searchController,
              autofocus: true,
              onChanged: (val) => setState(() => _query = val),
              style: const TextStyle(
                fontFamily: HygTypography.bodyFontFamily,
                fontSize: 13,
              ),
              decoration: InputDecoration(
                hintText: 'Search product...',
                hintStyle: const TextStyle(
                  fontFamily: HygTypography.bodyFontFamily,
                  fontSize: 13,
                  color: Color(0xFF94A3B8),
                ),
                prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF94A3B8)),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: HygColors.goldStrong),
                ),
              ),
            ),
          ),
        ),
        const Divider(height: 1, color: Color(0xFFE2E8F0)),
        Flexible(
          child: filtered.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(12.0),
                  child: Text(
                    'No products found.',
                    style: TextStyle(
                      fontFamily: HygTypography.bodyFontFamily,
                      color: Color(0xFF94A3B8),
                      fontSize: 13,
                    ),
                  ),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final item = filtered[index];
                    return InkWell(
                      onTap: () => widget.onSelect(item),
                      hoverColor: const Color(0xFFFEF3C7).withOpacity(0.5),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            item.itemName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: HygTypography.bodyFontFamily,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
