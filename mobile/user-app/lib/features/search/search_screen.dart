import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/hutube_widgets.dart';

/// Full-screen search shell. Search endpoints are not part of the current
/// mobile API contract, so submitting keeps the user on an honest empty state.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _query = TextEditingController();
  String _filter = 'all';

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
    children: [
      HuTubeSectionHeader(
        title: 'Tìm kiếm',
        subtitle: 'Tìm video, kênh và chủ đề trên HuTube.',
      ),
      const SizedBox(height: 18),
      TextField(
        controller: _query,
        autofocus: true,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => setState(() {}),
        decoration: InputDecoration(
          hintText: 'Bạn muốn xem gì hôm nay?',
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: _query.text.isEmpty
              ? null
              : IconButton(
                  onPressed: () => setState(_query.clear),
                  icon: const Icon(Icons.close_rounded),
                ),
        ),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 14),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final item in const [
              ('all', 'Tất cả'),
              ('video', 'Video'),
              ('channel', 'Kênh'),
              ('playlist', 'Playlist'),
            ])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(item.$2),
                  selected: _filter == item.$1,
                  onSelected: (_) => setState(() => _filter = item.$1),
                ),
              ),
          ],
        ),
      ),
      HuTubeStateView(
        icon: Icons.manage_search_rounded,
        title: _query.text.isEmpty
            ? 'Bắt đầu với một từ khóa'
            : 'Chưa có kết quả để hiển thị',
        message: _query.text.isEmpty
            ? 'Nhập tên video, kênh hoặc chủ đề để tìm nội dung bạn quan tâm.'
            : 'API tìm kiếm chưa được cung cấp cho mobile. Hãy thử khám phá theo chủ đề.',
        compact: true,
        accent: AppColors.violet,
      ),
    ],
  );
}
