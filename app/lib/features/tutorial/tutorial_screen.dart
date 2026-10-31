// How-to pages: shown automatically on the first launch, and again from the
// "?" button. Content is a placeholder until Bomin's tutorial design lands;
// replace _pages (and add images) without touching the flow.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/theme.dart';

/// First-launch flag stored as an empty file in the app support directory.
abstract final class TutorialGate {
  static Future<File> _flag() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/tutorial_seen');
  }

  static Future<bool> shouldShow() async {
    try {
      return !await (await _flag()).exists();
    } catch (_) {
      return false;
    }
  }

  static Future<void> markSeen() async {
    try {
      await (await _flag()).create(recursive: true);
    } catch (_) {
      // Worst case the tutorial shows again next launch.
    }
  }
}

class _Page {
  const _Page(this.icon, this.title, this.body);
  final IconData icon;
  final String title;
  final String body;
}

const _pages = [
  _Page(
    Icons.photo_camera_outlined,
    '사진 감각, 빌려드릴게요',
    '폰을 건네받은 사람도 화면의 한 줄 안내만 따라 하면\n원하는 구도로 찍을 수 있어요.',
  ),
  _Page(
    Icons.auto_awesome_outlined,
    '추천 · 맞춤',
    '추천: 아래 5단계 바로 인물과 배경의 비중을 고르면\n배경에 맞는 구도를 알려 줘요.\n\n맞춤: 원하는 사진을 레퍼런스로 넣으면 그 구도로 안내해요.',
  ),
  _Page(
    Icons.campaign_outlined,
    '안내를 따라 하고, 셔터는 직접',
    '가까워질수록 삐-삐 소리가 빨라지고,\n맞으면 딩 소리와 진동, 노란 테두리가 떠요.\n그때 셔터를 눌러 주세요.',
  ),
];

class TutorialScreen extends StatefulWidget {
  const TutorialScreen({super.key});

  @override
  State<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends State<TutorialScreen> {
  final _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    await TutorialGate.markSeen();
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final last = _index == _pages.length - 1;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _finish,
                child: const Text(
                  '건너뛰기',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) {
                  final page = _pages[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(page.icon, color: AppColors.accent, size: 72),
                        const SizedBox(height: 28),
                        Text(
                          page.title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppColors.text,
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          page.body,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 15,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _pages.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == _index ? 18 : 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: i == _index ? AppColors.accent : Colors.white30,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.black,
                  ),
                  onPressed: last
                      ? _finish
                      : () => _controller.nextPage(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOut,
                        ),
                  child: Text(
                    last ? '시작하기' : '다음',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
