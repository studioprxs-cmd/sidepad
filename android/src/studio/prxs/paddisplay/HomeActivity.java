package studio.prxs.paddisplay;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Intent;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.os.Bundle;
import android.view.Gravity;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;

public final class HomeActivity extends Activity {
    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        ScrollView scroll=new ScrollView(this);
        scroll.setFillViewport(true); scroll.setBackgroundColor(0xff0b1020);
        LinearLayout box=new LinearLayout(this); box.setOrientation(LinearLayout.VERTICAL);
        box.setPadding(dp(48),dp(28),dp(48),dp(28)); box.setGravity(Gravity.CENTER_VERTICAL);
        scroll.addView(box);
        TextView title=text("SidePad",36,Color.WHITE);
        title.setTypeface(null,Typeface.BOLD); box.addView(title);
        TextView subtitle=text("패드로 더 넓게 보세요",18,0xffaab7d1);
        LinearLayout.LayoutParams sub=new LinearLayout.LayoutParams(-1,-2);sub.bottomMargin=dp(20);
        box.addView(subtitle,sub);
        addMode(box,"Mac USB 모니터","USB로 Mac 화면을 확장합니다 · 펜과 터치 지원", "usb",0xff344bb7);
        addMode(box,"아이폰 화면 미러링","같은 Wi-Fi에서 연결 · 아이폰에 앱 설치 없이 AirPlay", "airplay",0xff5141b9);
        TextView help=text("사용할 연결 방식을 선택해 주세요.\n연결 화면에서 뒤로 가기를 누르면 이 메뉴로 돌아옵니다.",14,0xff96a5c1);
        help.setPadding(0,dp(12),0,0);box.addView(help);
        Button licenses=new Button(this);licenses.setText("오픈소스 라이선스");
        licenses.setOnClickListener(v -> showLicenses());box.addView(licenses);
        setContentView(scroll);
    }
    private void addMode(LinearLayout box,String title,String detail,String mode,int color) {
        LinearLayout card=new LinearLayout(this);card.setOrientation(LinearLayout.VERTICAL);
        card.setPadding(dp(24),dp(18),dp(24),dp(18));
        GradientDrawable bg=new GradientDrawable();bg.setColor(color);bg.setCornerRadius(dp(18));card.setBackground(bg);
        TextView heading=text(title,24,Color.WHITE);heading.setTypeface(null,Typeface.BOLD);
        card.addView(heading);card.addView(text(detail,15,0xffe1e6ff));
        card.setOnClickListener(v->open(mode));card.setFocusable(true);
        card.setContentDescription(title+". "+detail);
        LinearLayout.LayoutParams p=new LinearLayout.LayoutParams(-1,-2);p.bottomMargin=dp(12);box.addView(card,p);
    }
    private void open(String mode) {
        // Keep the chooser as the task root. A launcher tap returns to it even
        // when a previous receiver activity is still in the background.
        startActivity(new Intent(this, mode.equals("airplay")?AirPlayActivity.class:MainActivity.class));
    }
    private TextView text(String value,int size,int color) {
        TextView v=new TextView(this);v.setText(value);v.setTextSize(size);v.setTextColor(color);v.setPadding(0,dp(3),0,dp(3));return v;
    }
    private int dp(int n){return Math.round(n*getResources().getDisplayMetrics().density);}
    private void showLicenses() {
        try(InputStream input=getAssets().open("airplay-notices.txt")) {
            ByteArrayOutputStream bytes=new ByteArrayOutputStream();byte[] b=new byte[4096];int n;
            while((n=input.read(b))!=-1)bytes.write(b,0,n);
            TextView v=text(bytes.toString(StandardCharsets.UTF_8.name()),13,0xff222222);v.setPadding(dp(16),dp(8),dp(16),dp(8));
            ScrollView scroll=new ScrollView(this);scroll.addView(v);
            new AlertDialog.Builder(this).setTitle("오픈소스 라이선스").setView(scroll).setPositiveButton("닫기",null).show();
        } catch(Exception e) {new AlertDialog.Builder(this).setMessage("라이선스를 읽지 못했습니다.").setPositiveButton("닫기",null).show();}
    }
}
