package studio.prxs.paddisplay;

import android.app.Activity;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.graphics.Color;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.PixelFormat;
import android.graphics.PorterDuff;
import android.media.MediaCodec;
import android.media.MediaFormat;
import android.media.MediaCodecInfo;
import android.media.MediaCodecList;
import android.util.Base64;
import android.util.Log;
import android.view.Gravity;
import android.view.Display;
import android.view.MotionEvent;
import android.view.Surface;
import android.view.SurfaceControl;
import android.view.SurfaceHolder;
import android.view.SurfaceView;
import android.view.View;
import android.view.ViewConfiguration;
import android.view.WindowManager;
import android.widget.FrameLayout;
import android.widget.TextView;
import org.json.JSONObject;
import java.io.DataInputStream;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.ArrayDeque;

/** USB-only display receiver. It opens no listening port and requests no storage permission. */
public final class MainActivity extends Activity implements SurfaceHolder.Callback {
    private final Handler ui = new Handler(Looper.getMainLooper());
    private SurfaceView video;
    private TextView status;
    private CursorView cursor;
    private volatile Session session;
    private volatile boolean resumed, hasSurface;
    private String token = "";
    private int videoWidth = 1920, videoHeight = 1200;
    private TouchGesture touch;
    private boolean penContact,penInRange;
    private long lastPenTime=-10000;

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        setVolumeControlStream(android.media.AudioManager.STREAM_MUSIC);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        getWindow().getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_FULLSCREEN |
            View.SYSTEM_UI_FLAG_HIDE_NAVIGATION | View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY |
            View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION |
            View.SYSTEM_UI_FLAG_LAYOUT_STABLE);
        token = getIntent().getStringExtra("token");
        if (token == null) token = getPreferences(0).getString("token", "");
        else getPreferences(0).edit().putString("token", token).apply();
        FrameLayout root = new FrameLayout(this);
        root.setBackgroundColor(Color.BLACK);
        video = new SurfaceView(this);
        root.addView(video, new FrameLayout.LayoutParams(-1, -1, Gravity.CENTER));
        touch=new TouchGesture(ViewConfiguration.get(this).getScaledTouchSlop(),(action,x,y,dx,dy)->{
            Session current=session;if(current==null)return;
            ByteBuffer data=ByteBuffer.allocate(17);
            data.put((byte)action).putFloat(x).putFloat(y).putFloat(dx).putFloat(dy);
            current.sendInput(8,data.array());
        });
        video.setOnTouchListener((v,event) -> inputEvent(event));
        video.setOnHoverListener((v,event) -> penEvent(event));
        video.getHolder().addCallback(this);
        root.addOnLayoutChangeListener((v,l,t,r,b,ol,ot,or,ob) -> fitVideo());
        cursor = new CursorView();
        root.addView(cursor, new FrameLayout.LayoutParams(-1, -1));
        status = new TextView(this);
        status.setTextColor(0xffe6ebf5); status.setTextSize(18); status.setGravity(Gravity.CENTER);
        status.setBackgroundColor(0xcc111827);
        int pad = (int)(24 * getResources().getDisplayMetrics().density);
        status.setPadding(pad, pad, pad, pad);
        root.addView(status, new FrameLayout.LayoutParams(-1, -2, Gravity.CENTER));
        setContentView(root);
        showStatus("SidePad\nUSB를 연결하고 맥에서 ‘연결 시작’을 누르세요.");
    }
    @Override protected void onNewIntent(android.content.Intent intent) {
        super.onNewIntent(intent); setIntent(intent);
        String next = intent.getStringExtra("token");
        if (next != null) { token = next; getPreferences(0).edit().putString("token", next).apply(); }
        stopSession(); startIfReady();
    }
    private void requestFastDisplay() {
        Display display = getWindowManager().getDefaultDisplay();
        WindowManager.LayoutParams attrs = getWindow().getAttributes();
        for (Display.Mode mode : display.getSupportedModes()) {
            if (Math.abs(mode.getRefreshRate()-120f)<1f) {
                attrs.preferredDisplayModeId=mode.getModeId(); attrs.preferredRefreshRate=120f;
                getWindow().setAttributes(attrs);
                Log.i("PadDisplay","requested-display-hz=120 mode="+mode.getModeId()); break;
            }
        }
    }
    @Override protected void onResume() { super.onResume(); resumed = true; requestFastDisplay(); startIfReady(); }
    @Override protected void onPause() { resumed = false; stopSession(); super.onPause(); }
    @Override public void surfaceCreated(SurfaceHolder holder) {
        hasSurface = true;
        if(android.os.Build.VERSION.SDK_INT>=30) holder.getSurface().setFrameRate(120f,Surface.FRAME_RATE_COMPATIBILITY_DEFAULT);
        cursor.createLayer(); startIfReady();
    }
    @Override public void surfaceChanged(SurfaceHolder holder, int fmt, int w, int h) { }
    @Override public void surfaceDestroyed(SurfaceHolder holder) { hasSurface = false; stopSession(); cursor.releaseLayer(); }

    private void fitVideo() {
        View parent = (View)video.getParent();
        int w = parent.getWidth(), h = parent.getHeight();
        if (w == 0 || h == 0) return;
        double ratio = (double)videoWidth / videoHeight;
        int vw = w, vh = (int)(w / ratio);
        if (vh > h) { vh = h; vw = (int)(h * ratio); }
        FrameLayout.LayoutParams old = (FrameLayout.LayoutParams)video.getLayoutParams();
        if (old.width != vw || old.height != vh) video.setLayoutParams(new FrameLayout.LayoutParams(vw, vh, Gravity.CENTER));
    }
    private void showStatus(String text) { ui.post(() -> { status.setText(text); status.setVisibility(View.VISIBLE); }); }
    private boolean inputEvent(MotionEvent event) {
        for(int i=0;i<event.getPointerCount();i++){
            int tool=event.getToolType(i);
            if(tool==MotionEvent.TOOL_TYPE_STYLUS || tool==MotionEvent.TOOL_TYPE_ERASER)return penEvent(event);
        }
        int action=event.getActionMasked();
        if(action==MotionEvent.ACTION_CANCEL || (event.getFlags()&MotionEvent.FLAG_CANCELED)!=0){touch.cancel();return true;}
        int n=event.getPointerCount();int[] ids=new int[n];float[] xs=new float[n],ys=new float[n];
        for(int i=0;i<n;i++){
            if(event.getToolType(i)!=MotionEvent.TOOL_TYPE_FINGER){touch.block();return true;}
            ids[i]=event.getPointerId(i);xs[i]=event.getX(i);ys[i]=event.getY(i);
        }
        boolean blocked=penContact || penInRange || SystemClock.uptimeMillis()-lastPenTime<600;
        touch.event(action,event.getActionIndex(),ids,xs,ys,video.getWidth(),video.getHeight(),blocked);
        return true;
    }
    private boolean penEvent(MotionEvent event) {
        int index=-1;
        for(int i=0;i<event.getPointerCount();i++) {
            int tool=event.getToolType(i);
            if(tool==MotionEvent.TOOL_TYPE_STYLUS || tool==MotionEvent.TOOL_TYPE_ERASER) {index=i;break;}
        }
        if(index<0 || session==null || video.getWidth()==0 || video.getHeight()==0)return false;
        touch.block();lastPenTime=SystemClock.uptimeMillis();
        int masked=event.getActionMasked();
        if((masked==MotionEvent.ACTION_POINTER_DOWN || masked==MotionEvent.ACTION_POINTER_UP) && event.getActionIndex()!=index)return true;
        int action;
        switch(event.getActionMasked()) {
            case MotionEvent.ACTION_DOWN: case MotionEvent.ACTION_POINTER_DOWN: action=2;break;
            case MotionEvent.ACTION_UP: case MotionEvent.ACTION_POINTER_UP: action=3;break;
            case MotionEvent.ACTION_MOVE: action=1;break;
            case MotionEvent.ACTION_CANCEL: action=4;break;
            case MotionEvent.ACTION_HOVER_EXIT: action=5;break;
            case MotionEvent.ACTION_HOVER_ENTER: case MotionEvent.ACTION_HOVER_MOVE: action=0;break;
            default:return false;
        }
        if(action==2)penContact=true;
        if(action==3 || action==4)penContact=false;
        if(action==0)penInRange=true;
        if(action==4 || action==5)penInRange=false;
        float x=Math.max(0,Math.min(1,event.getX(index)/video.getWidth()));
        float y=Math.max(0,Math.min(1,event.getY(index)/video.getHeight()));
        ByteBuffer data=ByteBuffer.allocate(26);
        data.put((byte)action).put((byte)(event.getToolType(index)==MotionEvent.TOOL_TYPE_ERASER?2:1))
            .putInt(event.getButtonState()).putFloat(x).putFloat(y).putFloat(event.getPressure(index))
            .putFloat(event.getAxisValue(MotionEvent.AXIS_TILT,index)).putFloat(event.getAxisValue(MotionEvent.AXIS_ORIENTATION,index));
        session.sendInput(7,data.array());return true;
    }
    private void startIfReady() {
        if (!resumed || !hasSurface || session != null) return;
        if (token.isEmpty()) { showStatus("SidePad\n맥에서 ‘연결 시작’을 누르면 자동으로 연결됩니다."); return; }
        Session next = new Session(token); session = next;
        new Thread(next, "PadDisplay-USB").start();
    }
    private void stopSession() {
        if(touch!=null)touch.cancel();penContact=false;penInRange=false;lastPenTime=-10000;
        Session old = session; session = null;
        if (old != null) old.stop();
        if (cursor != null) cursor.position(0, 0, false);
    }

    private final class CursorView extends View {
        final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
        Bitmap image;
        float hotX=10,hotY=10;
        SurfaceControl layer;
        volatile float x, y; volatile boolean visible;
        boolean poseApplied, appliedVisible;
        float appliedX, appliedY;
        long positionSamples, positionUpdates, statsAt=SystemClock.uptimeMillis();
        CursorView() {
            super(MainActivity.this); setWillNotDraw(false);
            int resource=getResources().getIdentifier("mac_cursor","drawable",getPackageName());
            BitmapFactory.Options options=new BitmapFactory.Options();options.inScaled=false;
            image=BitmapFactory.decodeResource(getResources(),resource,options);
        }
        synchronized void setImage(byte[] data) {
            if(data.length<=8 || data.length>512*1024)return;
            ByteBuffer values=ByteBuffer.wrap(data);float hx=values.getFloat(),hy=values.getFloat();
            Bitmap next=BitmapFactory.decodeByteArray(data,8,data.length-8);
            if(next==null || next.getWidth()>512 || next.getHeight()>512 || !Float.isFinite(hx) || !Float.isFinite(hy))return;
            image=next;hotX=hx;hotY=hy;
            createLayer();position(x,y,visible);
            Log.i("PadDisplay","cursor-image=macOS size="+image.getWidth()+"x"+image.getHeight());
        }
        synchronized void createLayer() {
            if(android.os.Build.VERSION.SDK_INT<29) return;
            releaseLayer();
            try {
                SurfaceControl parent=video.getSurfaceControl();
                if(parent==null || !parent.isValid())return;
                layer=new SurfaceControl.Builder().setName("PadDisplay-Cursor")
                    .setParent(parent).setBufferSize(image.getWidth(),image.getHeight()).setFormat(PixelFormat.TRANSLUCENT).build();
                Surface surface=new Surface(layer);
                try {
                    Canvas canvas=surface.lockCanvas(null);
                    canvas.drawColor(Color.TRANSPARENT,PorterDuff.Mode.CLEAR);
                    canvas.drawBitmap(image,0,0,paint);
                    surface.unlockCanvasAndPost(canvas);
                } finally { surface.release(); }
                try(SurfaceControl.Transaction transaction=new SurfaceControl.Transaction()) {
                    transaction.setLayer(layer,10).setVisibility(layer,false).apply();
                }
                Log.i("PadDisplay","cursor-renderer=SurfaceControl direct-compositor=true");
            } catch(Exception e) { Log.w("PadDisplay","Cursor compositor fallback",e);releaseLayer(); }
        }
        synchronized void releaseLayer() {
            poseApplied=false;
            if(layer!=null) {
                try(SurfaceControl.Transaction transaction=new SurfaceControl.Transaction()) {
                    transaction.reparent(layer,null).apply();
                } catch(Exception ignored) { }
                layer.release();layer=null;
            }
        }
        synchronized void position(float nx, float ny, boolean show) {
            if(!Float.isFinite(nx) || !Float.isFinite(ny))return;
            x=nx;y=ny;visible=show;
            boolean inView=show && nx>=0 && nx<=1 && ny>=0 && ny<=1;
            float px=nx*video.getWidth()-hotX,py=ny*video.getHeight()-hotY;
            positionSamples++;
            long now=SystemClock.uptimeMillis();
            if(now-statsAt>=10000){
                Log.i("PadDisplay","cursor-window-ms="+(now-statsAt)+" positions="+positionSamples+" updates="+positionUpdates);
                statsAt=now;positionSamples=0;positionUpdates=0;
            }
            if(poseApplied && inView==appliedVisible && (!inView || (px==appliedX && py==appliedY)))return;
            if(layer!=null && layer.isValid()) {
                try(SurfaceControl.Transaction transaction=new SurfaceControl.Transaction()) {
                    transaction.setPosition(layer,px,py).setVisibility(layer,inView).apply();
                }
            } else postInvalidateOnAnimation();
            poseApplied=true;appliedVisible=inView;appliedX=px;appliedY=py;positionUpdates++;
        }
        @Override protected void onDraw(Canvas canvas) {
            synchronized(this) { if(layer!=null) return; }
            if (!visible || x<0 || x>1 || y<0 || y>1) return;
            float px=video.getLeft()+x*video.getWidth(), py=video.getTop()+y*video.getHeight();
            canvas.drawBitmap(image,px-hotX,py-hotY,paint);
        }
    }

    private MediaCodec createDecoder(int width, int height, int fps) throws Exception {
        String selected = null; int best = -1;
        for (MediaCodecInfo info : new MediaCodecList(MediaCodecList.ALL_CODECS).getCodecInfos()) {
            if (info.isEncoder() || info.getName().contains("secure")) continue;
            try {
                MediaCodecInfo.CodecCapabilities caps = info.getCapabilitiesForType("video/avc");
                if (!caps.getVideoCapabilities().areSizeAndRateSupported(width, height, fps)) continue;
                int score = 0;
                if (android.os.Build.VERSION.SDK_INT >= 29 && info.isHardwareAccelerated()) score += 100;
                if (android.os.Build.VERSION.SDK_INT >= 30 && caps.isFeatureSupported(MediaCodecInfo.CodecCapabilities.FEATURE_LowLatency)) score += 200;
                if (info.getName().contains("lowlatency")) score += 100;
                if (score > best) { selected = info.getName(); best = score; }
            } catch (IllegalArgumentException ignored) { }
        }
        return selected == null ? MediaCodec.createDecoderByType("video/avc") : MediaCodec.createByCodecName(selected);
    }

    private static final class InputPacket {
        final int type;final byte[] data;
        InputPacket(int type,byte[] data){this.type=type;this.data=data;}
    }
    private final class Session implements Runnable {
        final String secret;
        final AtomicBoolean active = new AtomicBoolean(true);
        volatile Socket socket;
        volatile Socket cursorSocket;
        volatile OutputStream cursorOutput;
        final Object cursorWriteLock=new Object();
        final ArrayDeque<InputPacket> inputEvents=new ArrayDeque<>();
        final UsbAudio audio;
        Session(String secret) { this.secret = secret;audio=new UsbAudio(MainActivity.this,secret); }
        void stop() { active.set(false);audio.stop(); synchronized(inputEvents){inputEvents.notifyAll();} try { if (socket != null) socket.close(); } catch (Exception ignored) { } try { if(cursorSocket!=null)cursorSocket.close(); } catch(Exception ignored){} }
        void sendInput(int type,byte[] data) {
            synchronized(inputEvents) {
                // Keep button boundaries; coalesce only consecutive movement samples.
                InputPacket last=inputEvents.peekLast();
                if((data[0]==0 || data[0]==1) && last!=null && last.type==type && last.data[0]==data[0])inputEvents.removeLast();
                inputEvents.addLast(new InputPacket(type,data));inputEvents.notifyAll();
            }
        }
        private void sendInputs() {
            android.os.Process.setThreadPriority(android.os.Process.THREAD_PRIORITY_DISPLAY);
            while(active.get()) {
                InputPacket message;
                synchronized(inputEvents) {
                    while(inputEvents.isEmpty() && active.get())try{inputEvents.wait();}catch(InterruptedException ignored){}
                    if(!active.get())return;message=inputEvents.removeFirst();
                }
                try {
                    synchronized(cursorWriteLock) {
                        OutputStream out=cursorOutput;if(out==null)continue;
                        ByteBuffer packet=ByteBuffer.allocate(5+message.data.length);packet.put((byte)message.type).putInt(message.data.length).put(message.data);
                        out.write(packet.array());out.flush();
                    }
                } catch(Exception e){if(active.get())Log.w("PadDisplay","Pen input reconnect: "+e);}
            }
        }
        @Override public void run() {
            new Thread(audio,"PadDisplay-Audio").start();
            new Thread(this::sendInputs,"PadDisplay-PenInput").start();
            Thread cursorThread = new Thread(this::receiveCursor, "PadDisplay-Cursor"); cursorThread.start();
            while (active.get()) {
                MediaCodec decoder = null;
                Thread renderer = null;
                AtomicBoolean decoding = new AtomicBoolean(false);
                try {
                    showStatus("USB 연결 중…\n맥의 SidePad를 실행해 주세요.");
                    Socket current = new Socket(); socket = current;
                    current.setTcpNoDelay(true);
                    current.connect(new InetSocketAddress("127.0.0.1", 28765), 3000);
                    // Idle desktops need not produce frames, so no socket read timeout is used.
                    OutputStream out = current.getOutputStream();
                    out.write(("PADDISPLAY/1 " + secret + "\n").getBytes(StandardCharsets.UTF_8)); out.flush();
                    DataInputStream input = new DataInputStream(current.getInputStream());
                    long received = 0;
                    while (active.get()) {
                        int type = input.readUnsignedByte();
                        int length = input.readInt();
                        if (length < 1 || length > 8 * 1024 * 1024) throw new Exception("잘못된 영상 패킷");
                        byte[] data = new byte[length]; input.readFully(data);
                        if (type == 1) {
                            if (decoder != null) continue;
                            JSONObject config = new JSONObject(new String(data, StandardCharsets.UTF_8));
                            int w = config.getInt("width"), h = config.getInt("height");
                            int fps = config.optInt("fps", 60);
                            if (w < 16 || h < 16 || w > 4096 || h > 4096) throw new Exception("지원하지 않는 해상도");
                            ui.post(() -> { videoWidth = w; videoHeight = h; fitVideo(); });
                            MediaFormat format = MediaFormat.createVideoFormat("video/avc", w, h);
                            format.setByteBuffer("csd-0", ByteBuffer.wrap(Base64.decode(config.getString("sps"), 0)));
                            format.setByteBuffer("csd-1", ByteBuffer.wrap(Base64.decode(config.getString("pps"), 0)));
                            format.setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 8 * 1024 * 1024);
                            format.setInteger(MediaFormat.KEY_PRIORITY, 0);
                            format.setInteger(MediaFormat.KEY_OPERATING_RATE, fps);
                            format.setInteger(MediaFormat.KEY_FRAME_RATE, fps);
                            if (android.os.Build.VERSION.SDK_INT >= 30) format.setInteger(MediaFormat.KEY_LOW_LATENCY, 1);
                            decoder = createDecoder(w, h, fps);
                            decoder.configure(format, video.getHolder().getSurface(), null, 0);
                            decoder.start();
                            final MediaCodec codec = decoder; decoding.set(true);
                            final long[] timing = {0, 0};
                            codec.setOnFrameRenderedListener((mc, pts, nanoTime) -> {
                                long latency = (System.nanoTime() - pts * 1000) / 1000000;
                                if (latency >= 0 && latency < 2000) { timing[0] += latency; timing[1]++; }
                                if (timing[1] == 120) { Log.i("PadDisplay", "decoder-to-display average-ms=" + timing[0]/120); timing[0] = 0; timing[1] = 0; }
                            }, ui);
                            renderer = new Thread(() -> {
                                MediaCodec.BufferInfo info = new MediaCodec.BufferInfo();
                                long frames = 0;
                                try {
                                    while (decoding.get() && active.get()) {
                                        int index = codec.dequeueOutputBuffer(info, 10000);
                                        if (index >= 0) {
                                            int next;
                                            while ((next = codec.dequeueOutputBuffer(info, 0)) >= 0) {
                                                codec.releaseOutputBuffer(index, false); index = next;
                                            }
                                            codec.releaseOutputBuffer(index, true);
                                            if (++frames == 1) ui.post(() -> status.setVisibility(View.GONE));
                                            if (frames % 120 == 0) Log.i("PadDisplay", "rendered=" + frames + " resolution=" + w + "x" + h);
                                        }
                                    }
                                } catch (Exception e) {
                                    if (active.get() && decoding.get()) { Log.e("PadDisplay", "decoder output", e); try { current.close(); } catch(Exception ignored){} }
                                }
                            }, "PadDisplay-Render"); renderer.start();
                            Log.i("PadDisplay", "decoder=" + decoder.getName() + " resolution=" + w + "x" + h);
                        } else if (type == 2 && decoder != null) {
                            int index;
                            do { index = decoder.dequeueInputBuffer(10000); } while (index < 0 && active.get());
                            if (index < 0) break;
                            ByteBuffer buffer = decoder.getInputBuffer(index);
                            if (buffer == null || buffer.capacity() < data.length) throw new Exception("영상 버퍼 크기 초과");
                            buffer.clear(); buffer.put(data);
                            decoder.queueInputBuffer(index, 0, data.length, System.nanoTime()/1000, 0);
                            received++;
                            if (received % 120 == 0) Log.i("PadDisplay", "received="+received+" resolution="+videoWidth+"x"+videoHeight);
                        }
                    }
                } catch (Exception e) {
                    if (active.get()) { Log.w("PadDisplay", "USB reconnect: " + e); showStatus("연결 대기 중…\nUSB 케이블과 맥의 SidePad를 확인하세요."); }
                } finally {
                    decoding.set(false);
                    if (renderer != null) try { renderer.join(1000); } catch (InterruptedException ignored) { }
                    if (decoder != null) { try { decoder.stop(); } catch(Exception ignored){} decoder.release(); }
                    try { if (socket != null) socket.close(); } catch(Exception ignored){}
                }
                if (active.get()) try { Thread.sleep(1200); } catch (InterruptedException ignored) { }
            }
        }
        private void receiveCursor() {
            android.os.Process.setThreadPriority(android.os.Process.THREAD_PRIORITY_DISPLAY);
            while(active.get()) {
                try {
                    Socket current = new Socket(); cursorSocket=current;
                    current.setTcpNoDelay(true); current.connect(new InetSocketAddress("127.0.0.1",28766),3000);
                    OutputStream output=current.getOutputStream();
                    synchronized(cursorWriteLock) {
                        output.write(("PADCURSOR/1 "+secret+"\n").getBytes(StandardCharsets.UTF_8));output.flush();cursorOutput=output;
                    }
                    DataInputStream input=new DataInputStream(current.getInputStream());long packets=0,lastEcho=0;
                    while(active.get()) {
                        int type=input.readUnsignedByte(), length=input.readInt();
                        if(type==6 && length>8 && length<=512*1024) {
                            byte[] image=new byte[length];input.readFully(image);
                            if(session==this)cursor.setImage(image);continue;
                        }
                        if(type!=4 || length!=17)throw new Exception("잘못된 커서 패킷");
                        byte[] data=new byte[17];input.readFully(data);
                        ByteBuffer values=ByteBuffer.wrap(data);boolean visible=values.get()!=0;
                        float x=values.getFloat(),y=values.getFloat();
                        if(session==this)cursor.position(x,y,visible);
                        long now=SystemClock.uptimeMillis();
                        if(++packets%10==0 || now-lastEcho>=100) {
                            ByteBuffer echo=ByteBuffer.allocate(22);echo.put((byte)5).putInt(17).put(data);
                            synchronized(cursorWriteLock){output.write(echo.array());output.flush();}
                            lastEcho=now;
                        }
                        if(packets%1200==0)Log.i("PadDisplay","cursor packets="+packets+" separate-channel=true");
                    }
                } catch(Exception e) {
                    if(active.get())Log.w("PadDisplay","Cursor reconnect: "+e);
                } finally {
                    synchronized(cursorWriteLock){cursorOutput=null;}
                    try{if(cursorSocket!=null)cursorSocket.close();}catch(Exception ignored){}
                    if(session==this)cursor.position(0,0,false);
                }
                if(active.get())try{Thread.sleep(1000);}catch(InterruptedException ignored){}
            }
        }
    }
}
