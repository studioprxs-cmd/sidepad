package studio.prxs.paddisplay;

import android.app.Activity;
import android.content.Intent;
import android.graphics.Color;
import android.graphics.Typeface;
import android.net.ConnectivityManager;
import android.net.Network;
import android.net.NetworkCapabilities;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;
import android.view.Gravity;
import android.view.SurfaceHolder;
import android.view.SurfaceView;
import android.view.View;
import android.view.WindowManager;
import android.widget.Button;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.TextView;

/** Visible-only receiver: leaving the activity withdraws discovery and stops native sockets/audio. */
public final class AirPlayActivity extends Activity implements SurfaceHolder.Callback {
    private final Handler ui=new Handler(Looper.getMainLooper());
    private SurfaceView surface;
    private FrameLayout root;
    private LinearLayout panel;
    private TextView heading,details;
    private boolean resumed,hasSurface;
    private int width=16,height=9;
    private String receiverName="SidePad";
    private String pairingCode="";
    private AirPlaySession session;
    private ConnectivityManager connectivity;
    private volatile Network observedNetwork;
    private final ConnectivityManager.NetworkCallback networkChanges=new ConnectivityManager.NetworkCallback(){
        @Override public void onLost(Network n){if(n.equals(observedNetwork)){observedNetwork=null;networkChanged();}}
        @Override public void onAvailable(Network n){if(!n.equals(observedNetwork)){observedNetwork=n;networkChanged();}}
    };
    private final Runnable restart=()->{if(resumed){stopReceiver();startIfReady();}};
    private void networkChanged(){ui.post(()->{ui.removeCallbacks(restart);ui.postDelayed(restart,700);});}
    @Override public void onCreate(Bundle state){
        super.onCreate(state);
        setVolumeControlStream(android.media.AudioManager.STREAM_MUSIC);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        getWindow().getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_FULLSCREEN|View.SYSTEM_UI_FLAG_HIDE_NAVIGATION|View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY|View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN|View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION|View.SYSTEM_UI_FLAG_LAYOUT_STABLE);
        root=new FrameLayout(this);root.setBackgroundColor(Color.BLACK);
        surface=new SurfaceView(this);surface.getHolder().addCallback(this);root.addView(surface,new FrameLayout.LayoutParams(-1,-1,Gravity.CENTER));
        root.addOnLayoutChangeListener((v,l,t,r,b,ol,ot,or,ob)->fit());
        panel=new LinearLayout(this);panel.setOrientation(LinearLayout.VERTICAL);panel.setPadding(dp(40),dp(24),dp(40),dp(24));panel.setGravity(Gravity.CENTER);panel.setBackgroundColor(0xf00b1020);
        heading=new TextView(this);heading.setTextColor(Color.WHITE);heading.setTextSize(28);heading.setTypeface(null,Typeface.BOLD);heading.setGravity(Gravity.CENTER);panel.addView(heading);
        details=new TextView(this);details.setTextColor(0xffbdcae2);details.setTextSize(17);details.setGravity(Gravity.CENTER);details.setPadding(0,dp(14),0,dp(14));panel.addView(details);
        LinearLayout buttons=new LinearLayout(this);buttons.setGravity(Gravity.CENTER);
        Button retry=new Button(this);retry.setText("다시 시도");retry.setOnClickListener(v->{stopReceiver();startIfReady();});buttons.addView(retry);
        Button wifi=new Button(this);wifi.setText("Wi-Fi 설정");wifi.setOnClickListener(v->startActivity(new Intent(Settings.ACTION_WIFI_SETTINGS)));buttons.addView(wifi);
        Button modes=new Button(this);modes.setText("연결 방식");modes.setOnClickListener(v->onBackPressed());buttons.addView(modes);panel.addView(buttons);
        root.addView(panel,new FrameLayout.LayoutParams(-1,-2,Gravity.CENTER));setContentView(root);
        connectivity=(ConnectivityManager)getSystemService(CONNECTIVITY_SERVICE);
        show("아이폰 화면 미러링","AirPlay 수신기를 시작하고 있습니다.");
    }
    @Override protected void onResume(){super.onResume();resumed=true;observedNetwork=connectivity.getActiveNetwork();connectivity.registerDefaultNetworkCallback(networkChanges);startIfReady();}
    @Override protected void onPause(){resumed=false;ui.removeCallbacks(restart);try{connectivity.unregisterNetworkCallback(networkChanges);}catch(RuntimeException ignored){}stopReceiver();super.onPause();}
    @Override protected void onDestroy(){ui.removeCallbacksAndMessages(null);super.onDestroy();}
    @Override public void onBackPressed(){stopReceiver();startActivity(new Intent(this,HomeActivity.class).putExtra("choose",true));finish();}
    @Override public void surfaceCreated(SurfaceHolder holder){hasSurface=true;startIfReady();}
    @Override public void surfaceChanged(SurfaceHolder holder,int format,int w,int h){}
    @Override public void surfaceDestroyed(SurfaceHolder holder){hasSurface=false;stopReceiver();}
    private boolean networkReady(){
        NetworkCapabilities c=connectivity.getNetworkCapabilities(connectivity.getActiveNetwork());
        return c!=null && (c.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)||c.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET));
    }
    private void startIfReady(){
        if(!resumed || !hasSurface || session!=null)return;
        if(!networkReady()){show("Wi-Fi에 연결해 주세요","아이폰과 패드를 같은 Wi-Fi에 연결한 뒤 ‘다시 시도’를 누르세요.");return;}
        show("AirPlay 준비 중","아이폰에 앱을 설치하지 않아도 됩니다.");
        pairingCode="";
        final AirPlaySession[] owner=new AirPlaySession[1];
        AirPlaySession.Listener listener=new AirPlaySession.Listener(){
            private void post(Runnable task){ui.post(()->{if(resumed && session==owner[0])task.run();});}
            public void ready(String name){post(()->{receiverName=name;waitingScreen();});}
            public void pin(String code){post(()->{pairingCode=code;waitingScreen();});}
            public void waiting(){post(()->waitingScreen());}
            public void size(int w,int h){post(()->{width=w;height=h;fit();});}
            public void rendered(){post(()->panel.setVisibility(View.GONE));}
            public void error(String message){post(()->show("연결을 확인해 주세요",message));}
        };
        session=owner[0]=new AirPlaySession(this,surface.getHolder().getSurface(),listener);session.start();
    }
    private void stopReceiver(){AirPlaySession old=session;session=null;if(old!=null)old.close();}
    private void waitingScreen(){show(receiverName+(pairingCode.isEmpty()?"":"\n연결 코드  "+pairingCode),"아이폰과 패드를 같은 Wi-Fi에 연결하세요.\n아이폰 제어 센터 → 화면 미러링 → 위 기기 이름 선택\n아이폰에서 비밀번호를 요구하면 위의 4자리 연결 코드를 입력하세요.\n\n뒤로 가기: 연결 방식 선택 · 앱을 나가면 연결 중지");}
    private void show(String title,String message){heading.setText(title);details.setText(message);panel.setVisibility(View.VISIBLE);}
    private void fit(){
        if(root.getWidth()==0 || root.getHeight()==0 || width<1 || height<1)return;
        int w=root.getWidth(),h=Math.round(w*(float)height/width);
        if(h>root.getHeight()){h=root.getHeight();w=Math.round(h*(float)width/height);}
        FrameLayout.LayoutParams p=(FrameLayout.LayoutParams)surface.getLayoutParams();
        if(p.width!=w || p.height!=h)surface.setLayoutParams(new FrameLayout.LayoutParams(w,h,Gravity.CENTER));
    }
    private int dp(int n){return Math.round(n*getResources().getDisplayMetrics().density);}
}
