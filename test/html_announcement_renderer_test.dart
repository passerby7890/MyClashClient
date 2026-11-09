// test/html_announcement_renderer_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flclash_v2board_client/presentation/widgets/html_announcement_renderer.dart';

void main() {
  const sampleHtml = '''
<p>亲爱的老客户与各位用户好：<br>
感谢大家九年一路以来的相伴与支持！面对近期国内机房大整改与严峻的网络环境，我们始终竭尽全力守护大家的连线品质。</p>

<h3>🔥 双十一年度狂欢：全年唯一一次 7 折特惠！</h3>
<p>双十一专属 7 折优惠码：<strong style="color: #e74c3c; font-size: 18px;">20261111</strong>（下单立享 <strong>7折</strong> 优惠！）</p>

<p><strong>💡 为什么强烈建议趁这次直接入手“年付/两年/三年”套餐？</strong><br>
1. <strong>折上加折最划算：</strong>长期套餐本身已自带超低折扣（年付约73折、两年65折、三年59折），现在输入优惠码再打 <strong>7折</strong>！折合下来<strong>买一年直接半价</strong>（每月最低只要 18.3 元起），<strong>买三年更是低至 41 折</strong>（每月仅 14.8 元起），单月续费绝对拿不到这种底价！<br>
2. <strong>没到期也能直接买：</strong>不用等旧套餐用完！现在直接下单长期套餐，系统会自动将您现有套餐的<strong>“剩余天数折算成现金余额”</strong>，直接抵扣新订单金额，一分钱都不浪费！一年就这一次超值特价，搭配九年老店信誉，趁现在锁单最省心！</p>

<hr>

<h3>⚠️ 近期网络与订阅重要提示</h3>
<p>1. <strong>国内机房大整改：</strong>近日外部网络波动剧烈，如遇无法连线或超时，请尝试<strong>“更新订阅”</strong>或<strong>“重新启动客户端”</strong>，敬请见谅。<br>
2. <strong>小火箭用户注意：</strong>使用 Shadowrocket（小火箭）请务必更新到最新版。<br>
3. <strong>获取订阅或签到亦可私聊 Telegram Bot：</strong> <a href="https://t.me/THJSQBOT" target="_blank"><strong>👉 点击私聊官方机器人 (@THJSQBOT)</strong></a></p>

<hr>

<h3>📥 全新客户端下载与更新</h3>
<p><strong>【安卓安装特别提醒】</strong>全新版本客户端已正式上线！小米、华为等部分国行手机近期会将代理客户端判定为限制安装应用，若遇到无法直接安装的情况，请透过 <strong>ADB 方式</strong>自行安装处理。</p>

<p><strong>📱 安卓端应用 (Android)</strong><br>
<a href="https://portal.0n23.li/d/android.apk" target="_blank">海外下载</a> | 
<a href="https://download99.oss-cn-hongkong.aliyuncs.com/new/android-arm64-v8a.zip" target="_blank">中国下载1</a> | 
<a href="https://oss-1317953906.cos.ap-shanghai.myqcloud.com/android.zip" target="_blank">中国下载2</a></p>

<p><strong>💻 Windows端应用</strong><br>
<a href="https://portal.0n23.li/d/windows.zip" target="_blank">海外下载</a> | 
<a href="https://download99.oss-cn-hongkong.aliyuncs.com/new/windows-amd64-setup.zip" target="_blank">中国下载1</a> | 
<a href="https://oss-1317953906.cos.ap-shanghai.myqcloud.com/windows.zip" target="_blank">中国下载2</a></p>

<p><strong>🍎 Mac端应用 (ARM核心 - M1/M2/M3/M4芯片)</strong><br>
<a href="https://portal.0n23.li/d/mac.dmg" target="_blank">海外下载</a> | 
<a href="https://download99.oss-cn-hongkong.aliyuncs.com/new/macos-arm64.dmg" target="_blank">中国下载1</a> | 
<a href="https://oss-1317953906.cos.ap-shanghai.myqcloud.com/mac.dmg" target="_blank">中国下载2</a></p>

<p><strong>🍎 Mac端应用 (X86核心 - Intel芯片)</strong><br>
<a href="https://download99.oss-cn-hongkong.aliyuncs.com/new/macos-amd64.dmg" target="_blank">点击下载</a></p>

<p><strong>* 客户端如出现问题，请重新下载安装新版本！再次感谢大家九年来的理解与支持！</strong></p>
''';

  test('CouponExtractor extracts 20261111 correctly', () {
    final coupon = CouponExtractor.extract(sampleHtml);
    expect(coupon, '20261111');
  });

  testWidgets('HtmlAnnouncementRenderer renders full Double 11 announcement cleanly', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: HtmlAnnouncementRenderer(html: sampleHtml),
          ),
        ),
      ),
    );

    // Verify dividers (<hr>) are rendered
    expect(find.byType(Divider), findsNWidgets(2));

    // Verify rich text spans contain key elements
    expect(find.textContaining('双十一专属 7 折优惠码：'), findsOneWidget);
    expect(find.textContaining('20261111'), findsOneWidget);
    expect(find.textContaining('海外下载'), findsWidgets);
    expect(find.textContaining('👉 点击私聊官方机器人 (@THJSQBOT)'), findsOneWidget);

    // Verify emoji presence
    expect(find.textContaining('🔥 双十一年度狂欢'), findsOneWidget);
    expect(find.textContaining('⚠️ 近期网络与订阅重要提示'), findsOneWidget);
    expect(find.textContaining('📥 全新客户端下载与更新'), findsOneWidget);
  });
}

