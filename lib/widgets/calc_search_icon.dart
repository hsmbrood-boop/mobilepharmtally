import 'package:flutter/material.dart';

/// 계산기 + 돋보기 조합 아이콘.
///
/// 둥근 사각형 칩(파란 그라디언트 + 그림자) 위에
/// 흰색 계산기와 노란 원 안의 돋보기를 얹어 작은 크기에서도
/// 시각적으로 또렷하게 보이도록 디자인.
class CalcSearchIcon extends StatelessWidget {
  const CalcSearchIcon({
    super.key,
    this.width = 50,
    this.height = 38,
  });

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E88E5), Color(0xFF0D47A1)],
        ),
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
        border: Border.all(color: const Color(0xFF0B3D91), width: 1),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 4,
            top: 3,
            child: Icon(
              Icons.calculate_rounded,
              color: Colors.white,
              size: height - 8,
            ),
          ),
          Positioned(
            right: 2,
            bottom: 1,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(
                color: Color(0xFFFFC107),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Color(0x66000000),
                    blurRadius: 2,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
              child: Icon(
                Icons.search_rounded,
                color: const Color(0xFF0D47A1),
                size: (height * 0.42).clamp(12.0, 18.0),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
