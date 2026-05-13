import 'package:flutter/material.dart';

/// 앱 시작/종료 시 공통으로 사용하는 브랜딩 화면.
///
/// 흰 배경 가운데에 앱 아이콘과 "Developed by HSM of Orc Holdings"
/// 문구를 보여준다. 문구는 굵게 표시하고 빨간색 둥근 테두리로 감싸 강조한다.
/// 종료 화면용으로 사용할 때는 [tagline] 에 마침표가 붙은 버전을 넘겨
/// 시각적으로 살짝 구분할 수 있게 한다.
///
/// 네이티브 스플래시(아이콘만, 텍스트 없음) → 이 화면(아이콘 + 텍스트)
/// 으로 전환될 때 점프가 도드라지지 않도록 텍스트를 짧게 페이드인한다.
/// 아이콘 자체는 네이티브 스플래시와 같은 위치 ·비슷한 크기로 두어 시각적
/// 연속성을 유지한다.
class BrandSplash extends StatefulWidget {
  const BrandSplash({super.key, this.tagline = 'Developed by HSM of Orc Holdings'});

  final String tagline;

  @override
  State<BrandSplash> createState() => _BrandSplashState();
}

class _BrandSplashState extends State<BrandSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    )..forward();
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 아이콘 크기: 네이티브 스플래시(안드로이드 12+ 시스템 마스크
              // 안에 들어간 splash 이미지) 가 표시하는 크기와 정확히 같게.
              // splash 이미지 캔버스(1024)에서 아이콘이 55% 차지 → 시스템
              // 240dp 캔버스에서 132dp 로 표시 → 여기서도 132dp.
              Image.asset(
                'assets/icons/pharm_tally_app_icon.png',
                width: 132,
                height: 132,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 28),
              // 텍스트만 짧게 페이드인 → 네이티브 스플래시에는 텍스트가 없으므로
              // "글자가 작아졌다 커졌다" 두 번 보이는 현상이 없어진다.
              FadeTransition(
                opacity: _fade,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 22, vertical: 12),
                    decoration: BoxDecoration(
                      // 빨간색 둥근 테두리(타원 느낌). 손글씨 같은 강조 효과를
                      // 깔끔한 Material 스타일로 재현.
                      border: Border.all(
                        color: const Color(0xFFD32F2F),
                        width: 2.5,
                      ),
                      borderRadius: BorderRadius.circular(60),
                    ),
                    child: Text(
                      widget.tagline,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF222222),
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// 시작용 StartupSplash 는 사용자가 "화면이 두 번 바뀐다"고 느끼는 문제가
// 있어 제거했다. 시작 시에는 시스템 스플래시 → 매출/정산 화면 직행.
// BrandSplash 는 종료 시 한 번 표시되는 용도로만 유지한다.

/// 매출/정산·현금정산 화면 맨 아래에 표시되는 작은 브랜딩 배지.
///
/// [BrandSplash] 에서 사용하는 "빨간 둥근 테두리 + 굵은 글자" 패턴의
/// 축소판. 한 줄 짜리라 화면 푸터에 가볍게 놓아도 부담 없다.
class BrandTaglineBadge extends StatelessWidget {
  const BrandTaglineBadge({
    super.key,
    this.text = 'Developed by HSM of Orc Holdings.',
  });

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      alignment: Alignment.center,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        decoration: BoxDecoration(
          border: Border.all(
            color: const Color(0xFFD32F2F),
            width: 2,
          ),
          borderRadius: BorderRadius.circular(40),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: Color(0xFF222222),
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}
