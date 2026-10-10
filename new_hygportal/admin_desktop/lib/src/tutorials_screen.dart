part of '../main.dart';

class HygTutorialsScreen extends StatefulWidget {
  const HygTutorialsScreen({super.key});

  @override
  State<HygTutorialsScreen> createState() => _HygTutorialsScreenState();
}

class _HygTutorialsScreenState extends State<HygTutorialsScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<PortalTutorialItem> _tutorials = [];
  bool _isLoading = true;
  String? _error;
  String _activeFilter = 'All'; // 'All', 'Active', 'Inactive'

  @override
  void initState() {
    super.initState();
    _loadTutorials();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadTutorials() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final items = await TutorialService.getTutorials();
      if (mounted) {
        setState(() {
          _tutorials = items;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  List<PortalTutorialItem> get _filteredTutorials {
    final query = _searchController.text.trim().toLowerCase();
    return _tutorials.where((item) {
      if (_activeFilter == 'Active' && !item.isActive) return false;
      if (_activeFilter == 'Inactive' && item.isActive) return false;

      if (query.isEmpty) return true;
      return item.title.toLowerCase().contains(query) ||
          item.description.toLowerCase().contains(query) ||
          item.youtubeUrl.toLowerCase().contains(query);
    }).toList();
  }

  Future<void> _openAddEditModal([PortalTutorialItem? existing]) async {
    final isEditing = existing != null;
    final titleController = TextEditingController(text: existing?.title ?? '');
    final urlController = TextEditingController(text: existing?.youtubeUrl ?? '');
    final descController = TextEditingController(text: existing?.description ?? '');
    bool isActive = existing?.isActive ?? true;
    bool isSubmitting = false;
    String? dialogError;

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            final currentUrl = urlController.text.trim();
            final videoId = TutorialService.extractYouTubeVideoId(currentUrl);
            final hasValidVideo = videoId.isNotEmpty;

            return Dialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Container(
                width: 580,
                padding: const EdgeInsets.all(24),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header
                      Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: const Color(0xFFEEF2FF),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Center(
                              child: HygTutorialsIcon(
                                size: 22,
                                color: Color(0xFF4F46E5),
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isEditing ? 'Edit Tutorial' : 'Add New Tutorial',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: HygColors.ink,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                const Text(
                                  'Enter tutorial title and YouTube video URL for HYG Portal App.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 20, color: Color(0xFF94A3B8)),
                            onPressed: () => Navigator.of(dialogCtx).pop(false),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      const Divider(color: Color(0xFFE2E8F0), height: 1),
                      const SizedBox(height: 20),

                      // Tutorial Name
                      const Text(
                        'Tutorial Name *',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: titleController,
                        decoration: InputDecoration(
                          hintText: 'e.g., How to Submit Time Requests (ESARF)',
                          hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                          prefixIcon: const Icon(Icons.title, size: 18, color: Color(0xFF64748B)),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 1.5),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // YouTube URL
                      const Text(
                        'YouTube Video URL *',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: urlController,
                        onChanged: (_) => setDialogState(() {}),
                        decoration: InputDecoration(
                          hintText: 'e.g., https://www.youtube.com/watch?v=... or https://youtu.be/...',
                          hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                          prefixIcon: const Icon(Icons.smart_display_outlined, size: 18, color: Color(0xFFDC2626)),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 1.5),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Live YouTube Thumbnail Preview Box
                      if (hasValidVideo)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0FDF4),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFF86EFAC)),
                          ),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  'https://img.youtube.com/vi/$videoId/hqdefault.jpg',
                                  width: 96,
                                  height: 54,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                    width: 96,
                                    height: 54,
                                    color: const Color(0xFFCBD5E1),
                                    child: const Icon(Icons.movie, color: Colors.white, size: 28),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Row(
                                      children: [
                                        Icon(Icons.check_circle, color: Color(0xFF16A34A), size: 16),
                                        SizedBox(width: 6),
                                        Text(
                                          'Valid YouTube Video Link',
                                          style: TextStyle(
                                            color: Color(0xFF16A34A),
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Video ID: $videoId',
                                      style: const TextStyle(
                                        color: Color(0xFF475569),
                                        fontSize: 12,
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              TextButton.icon(
                                onPressed: () => TutorialService.launchUrlInBrowser(currentUrl),
                                icon: const Icon(Icons.open_in_new, size: 14, color: Color(0xFF0284C7)),
                                label: const Text('Test Link', style: TextStyle(fontSize: 12, color: Color(0xFF0284C7))),
                              ),
                            ],
                          ),
                        )
                      else if (currentUrl.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF7ED),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFFDBA74)),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.info_outline, size: 16, color: Color(0xFFD97706)),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Paste a valid YouTube link (e.g. youtube.com/watch?v=... or youtu.be/...)',
                                  style: TextStyle(fontSize: 12, color: Color(0xFFB45309)),
                                ),
                              ),
                            ],
                          ),
                        ),

                      const SizedBox(height: 16),

                      // Optional Description
                      const Text(
                        'Description / Notes (Optional)',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: descController,
                        maxLines: 3,
                        decoration: InputDecoration(
                          hintText: 'Brief summary of topics covered in this video...',
                          hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 1.5),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Active Switch
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Visible in HYG Portal App',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF1E293B),
                                    ),
                                  ),
                                  Text(
                                    isActive
                                        ? 'Active — Users can browse and watch this tutorial'
                                        : 'Hidden — Hidden from standard user view',
                                    style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: isActive,
                              activeColor: const Color(0xFF4F46E5),
                              onChanged: (val) => setDialogState(() => isActive = val),
                            ),
                          ],
                        ),
                      ),

                      if (dialogError != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF2F2),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFFCA5A5)),
                          ),
                          child: Text(
                            dialogError!,
                            style: const TextStyle(color: Color(0xFFDC2626), fontSize: 12),
                          ),
                        ),
                      ],

                      const SizedBox(height: 24),

                      // Actions
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          OutlinedButton(
                            onPressed: isSubmitting ? null : () => Navigator.of(dialogCtx).pop(false),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF475569),
                              side: const BorderSide(color: Color(0xFFCBD5E1)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                            ),
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton.icon(
                            onPressed: isSubmitting
                                ? null
                                : () async {
                                    final name = titleController.text.trim();
                                    final url = urlController.text.trim();
                                    if (name.isEmpty) {
                                      setDialogState(() => dialogError = 'Please enter a tutorial name.');
                                      return;
                                    }
                                    if (url.isEmpty) {
                                      setDialogState(() => dialogError = 'Please enter a YouTube video URL.');
                                      return;
                                    }
                                    if (!hasValidVideo) {
                                      setDialogState(() => dialogError =
                                          'Could not identify YouTube video ID. Check that URL is valid.');
                                      return;
                                    }

                                    setDialogState(() {
                                      isSubmitting = true;
                                      dialogError = null;
                                    });

                                    try {
                                      if (isEditing) {
                                        await TutorialService.updateTutorial(
                                          id: existing.id,
                                          title: name,
                                          youtubeUrl: url,
                                          description: descController.text.trim(),
                                          isActive: isActive,
                                        );
                                      } else {
                                        await TutorialService.createTutorial(
                                          title: name,
                                          youtubeUrl: url,
                                          description: descController.text.trim(),
                                          isActive: isActive,
                                        );
                                      }
                                      if (dialogCtx.mounted) {
                                        Navigator.of(dialogCtx).pop(true);
                                      }
                                    } catch (e) {
                                      setDialogState(() {
                                        dialogError = 'Error saving tutorial: $e';
                                        isSubmitting = false;
                                      });
                                    }
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF4F46E5),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                              elevation: 0,
                            ),
                            icon: isSubmitting
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Icon(Icons.check, size: 18),
                            label: Text(isEditing ? 'Save Changes' : 'Add Tutorial'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (saved == true) {
      _loadTutorials();
    }
  }

  Future<void> _confirmDelete(PortalTutorialItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 24),
            SizedBox(width: 10),
            Text('Delete Tutorial?', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18)),
          ],
        ),
        content: Text('Are you sure you want to delete "${item.title}"? Users will no longer see this tutorial in the app.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await TutorialService.deleteTutorial(item.id);
        _loadTutorials();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete tutorial: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredTutorials;

    return Scaffold(
      backgroundColor: HygColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(context),
              const SizedBox(height: 14),
              _buildControlBar(),
              const SizedBox(height: 14),
              Expanded(
                child: _isLoading
                    ? Center(child: CircularProgressIndicator())
                    : _error != null
                        ? _buildErrorState()
                        : filtered.isEmpty
                            ? _buildEmptyState()
                            : _buildTutorialsGrid(filtered),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: HygColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6366F1), Color(0xFF4F46E5)],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Center(
              child: HygTutorialsIcon(size: 24, color: Colors.white),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'HYG Portal Tutorials',
                      style: TextStyle(
                        color: Color(0xFF0F172A),
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFFECACA)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.smart_display, size: 13, color: Color(0xFFDC2626)),
                          SizedBox(width: 4),
                          Text(
                            'YouTube Powered',
                            style: TextStyle(color: Color(0xFFDC2626), fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                const Text(
                  'Manage video guides and YouTube walkthrough tutorials accessible by employees in the HYG Portal App.',
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 13,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton.icon(
            onPressed: () => _openAddEditModal(),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4F46E5),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              elevation: 0,
            ),
            icon: const Icon(Icons.add, size: 16),
            label: const Text(
              'Add Tutorial',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF0F172A), size: 20),
            onPressed: _loadTutorials,
            tooltip: 'Refresh Tutorials',
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).pop(),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF0F172A),
              side: const BorderSide(color: Color(0xFFCBD5E1)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            icon: const Icon(Icons.arrow_back, size: 16),
            label: const Text(
              'Back',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlBar() {
    final activeCount = _tutorials.where((t) => t.isActive).length;
    final totalCount = _tutorials.length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: HygColors.border),
      ),
      child: Row(
        children: [
          // Search box
          Expanded(
            child: SizedBox(
              height: 38,
              child: TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Search tutorials by name, description, or URL...',
                  hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                  prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF64748B)),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),

          // Filter chips
          _buildFilterChip('All', 'All ($totalCount)'),
          const SizedBox(width: 6),
          _buildFilterChip('Active', 'Active ($activeCount)'),
          const SizedBox(width: 6),
          _buildFilterChip('Inactive', 'Inactive (${totalCount - activeCount})'),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String filterKey, String label) {
    final isSelected = _activeFilter == filterKey;
    return InkWell(
      onTap: () => setState(() => _activeFilter = filterKey),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFEEF2FF) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? const Color(0xFF818CF8) : const Color(0xFFE2E8F0),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? const Color(0xFF4F46E5) : const Color(0xFF64748B),
          ),
        ),
      ),
    );
  }

  Widget _buildTutorialsGrid(List<PortalTutorialItem> items) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Compute columns based on width
        int crossAxisCount = 3;
        if (constraints.maxWidth < 750) {
          crossAxisCount = 1;
        } else if (constraints.maxWidth < 1150) {
          crossAxisCount = 2;
        } else if (constraints.maxWidth < 1600) {
          crossAxisCount = 3;
        } else {
          crossAxisCount = 4;
        }

        const double crossAxisSpacing = 16;
        final double itemWidth =
            (constraints.maxWidth - (crossAxisCount - 1) * crossAxisSpacing) / crossAxisCount;
        final double thumbnailHeight = itemWidth * 9 / 16;
        // Info height: accommodates 2-line title, 2-line description, 8px spacing, and action row
        const double infoHeight = 126;
        final double totalCardHeight = thumbnailHeight + infoHeight;
        final double dynamicAspectRatio = (itemWidth / totalCardHeight).clamp(1.05, 1.45);

        return GridView.builder(
          padding: const EdgeInsets.only(bottom: 20),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: crossAxisSpacing,
            mainAxisSpacing: 16,
            childAspectRatio: dynamicAspectRatio,
          ),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final tutorial = items[index];
            return _buildTutorialCard(tutorial);
          },
        );
      },
    );
  }

  Widget _buildTutorialCard(PortalTutorialItem tutorial) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: HygColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Video Thumbnail Preview with YouTube play overlay (16:9 ratio)
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
                    child: tutorial.thumbnailUrl.isNotEmpty
                        ? Image.network(
                            tutorial.thumbnailUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _buildFallbackThumbnail(),
                          )
                        : _buildFallbackThumbnail(),
                  ),
                ),
                // Play overlay button
                Center(
                  child: InkWell(
                    onTap: () => TutorialService.launchUrlInBrowser(tutorial.youtubeUrl),
                    borderRadius: BorderRadius.circular(30),
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white.withValues(alpha: 0.8), width: 2),
                      ),
                      child: const Center(
                        child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 32),
                      ),
                    ),
                  ),
                ),
                // YouTube pill top-left
                Positioned(
                  top: 10,
                  left: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDC2626),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.play_arrow, color: Colors.white, size: 12),
                        SizedBox(width: 3),
                        Text(
                          'YouTube',
                          style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ),
                // Status chip top-right
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: tutorial.isActive
                          ? const Color(0xFF16A34A).withValues(alpha: 0.9)
                          : const Color(0xFF64748B).withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      tutorial.isActive ? 'Active' : 'Hidden',
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Video Information & Actions
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title (up to 2 lines)
                  Text(
                    tutorial.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                      height: 1.25,
                    ),
                  ),
                  // Description (strictly limited to 2 lines in preview)
                  if (tutorial.description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      tutorial.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF64748B),
                        height: 1.25,
                      ),
                    ),
                  ],
                  // Clean, adjusted spacing between description and YouTube Video URL
                  const SizedBox(height: 8),

                  // URL Link & Action Buttons
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () => TutorialService.launchUrlInBrowser(tutorial.youtubeUrl),
                          borderRadius: BorderRadius.circular(4),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              children: [
                                const Icon(Icons.link, size: 14, color: Color(0xFF0284C7)),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    tutorial.youtubeUrl,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFF0284C7),
                                      decoration: TextDecoration.underline,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 18, color: Color(0xFF475569)),
                        onPressed: () => _openAddEditModal(tutorial),
                        tooltip: 'Edit Tutorial',
                        constraints: const BoxConstraints(),
                        padding: const EdgeInsets.all(5),
                      ),
                      const SizedBox(width: 2),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFDC2626)),
                        onPressed: () => _confirmDelete(tutorial),
                        tooltip: 'Delete Tutorial',
                        constraints: const BoxConstraints(),
                        padding: const EdgeInsets.all(5),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFallbackThumbnail() {
    return Container(
      color: const Color(0xFF1E293B),
      child: const Center(
        child: Icon(Icons.smart_display_outlined, color: Colors.white54, size: 48),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Container(
        width: 420,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: HygColors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: const Color(0xFFEEF2FF),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Center(
                child: HygTutorialsIcon(size: 32, color: Color(0xFF4F46E5)),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'No Tutorials Found',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Add video tutorials with YouTube URLs so that staff and users can view and learn via the HYG Portal App.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Color(0xFF64748B), height: 1.4),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () => _openAddEditModal(),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4F46E5),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add First Tutorial'),
            ),
          ],
        ),
      ),
    );
  }

  static const String _migrationSql = '''-- Migration 0184: Create portal_tutorials table for YouTube video guides
CREATE TABLE IF NOT EXISTS public.portal_tutorials (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title TEXT NOT NULL,
  youtube_url TEXT NOT NULL,
  video_id TEXT NOT NULL DEFAULT '',
  description TEXT DEFAULT '',
  sort_order INTEGER DEFAULT 0,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.portal_tutorials ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Allow read access to portal_tutorials" ON public.portal_tutorials;
DROP POLICY IF EXISTS "Allow authenticated insert portal_tutorials" ON public.portal_tutorials;
DROP POLICY IF EXISTS "Allow authenticated update portal_tutorials" ON public.portal_tutorials;
DROP POLICY IF EXISTS "Allow authenticated delete portal_tutorials" ON public.portal_tutorials;

CREATE POLICY "Allow read access to portal_tutorials"
  ON public.portal_tutorials FOR SELECT
  TO authenticated, anon
  USING (true);

CREATE POLICY "Allow authenticated insert portal_tutorials"
  ON public.portal_tutorials FOR INSERT
  TO authenticated
  WITH CHECK (true);

CREATE POLICY "Allow authenticated update portal_tutorials"
  ON public.portal_tutorials FOR UPDATE
  TO authenticated
  USING (true)
  WITH CHECK (true);

CREATE POLICY "Allow authenticated delete portal_tutorials"
  ON public.portal_tutorials FOR DELETE
  TO authenticated
  USING (true);

CREATE OR REPLACE FUNCTION public.get_portal_tutorials()
RETURNS TABLE (
  id UUID,
  title TEXT,
  youtube_url TEXT,
  video_id TEXT,
  description TEXT,
  sort_order INTEGER,
  is_active BOOLEAN,
  created_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS \$\$
BEGIN
  RETURN QUERY
  SELECT t.id, t.title, t.youtube_url, t.video_id, t.description, t.sort_order, t.is_active, t.created_at, t.updated_at
  FROM public.portal_tutorials t
  ORDER BY t.sort_order ASC, t.created_at DESC;
END;
\$\$;
''';

  Widget _buildErrorState() {
    final isDbSetup = _error != null &&
        (_error!.toLowerCase().contains('database setup') ||
            _error!.toLowerCase().contains('portal_tutorials') ||
            _error!.toLowerCase().contains('0184') ||
            _error!.toLowerCase().contains('schema cache'));

    if (isDbSetup) {
      return Center(
        child: Container(
          width: 520,
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFFDBA74)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0F000000),
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFFED7AA)),
                ),
                child: const Icon(Icons.storage_rounded, size: 30, color: Color(0xFFEA580C)),
              ),
              const SizedBox(height: 16),
              const Text(
                'Database Table Setup Required',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF9A3412)),
              ),
              const SizedBox(height: 8),
              const Text(
                'The "portal_tutorials" table is not created in your Supabase database yet. '
                'Execute migration 0184 in your Supabase SQL Editor to enable tutorials.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Color(0xFF64748B), height: 1.4),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: () {
                      Clipboard.setData(const ClipboardData(text: _migrationSql));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Migration SQL copied to clipboard! Paste and run it in Supabase SQL Editor.'),
                          backgroundColor: Color(0xFF166534),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFEA580C),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    label: const Text('Copy Migration SQL', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: _loadTutorials,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF475569),
                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Check Again'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return Center(
      child: Container(
        width: 440,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFFCA5A5)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 40, color: Color(0xFFDC2626)),
            const SizedBox(height: 12),
            const Text(
              'Failed to Load Tutorials',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF991B1B)),
            ),
            const SizedBox(height: 6),
            Text(
              _error ?? 'An unexpected error occurred while fetching tutorials.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadTutorials,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4F46E5),
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }
}

