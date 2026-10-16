package studio.prxs.paddisplay;

import android.media.MediaCodec;
import android.media.MediaCodecInfo;
import android.media.MediaCodecList;
import android.media.MediaFormat;
import android.os.Build;
import android.os.Handler;
import android.os.HandlerThread;
import android.util.Log;
import android.view.Surface;
import java.nio.ByteBuffer;
import java.util.ArrayList;
import java.util.Comparator;

/** Decode on one worker; drain continuously so the last received frame also reaches the screen. */
final class AirPlayVideo {
    interface Listener {void size(int width,int height);void rendered();void error(String message);}
    private final HandlerThread thread=new HandlerThread("SidePad-AirPlay-video");
    private final Handler worker;
    private final Surface surface;
    private final Listener listener;
    private final AirPlayFrames frames=new AirPlayFrames();
    private final AirPlayLatency latency=new AirPlayLatency();
    private final java.util.HashSet<String> failedDecoders=new java.util.HashSet<>();
    private final MediaCodec.BufferInfo info=new MediaCodec.BufferInfo();
    private MediaCodec codec;
    private volatile boolean closed;
    private boolean pumping,firstFrame;
    private long configuredGeneration=-1;
    private AirPlayFrames.Frame pending;
    private String decoderName="";
    AirPlayVideo(Surface surface,Listener listener){this.surface=surface;this.listener=listener;thread.start();worker=new Handler(thread.getLooper());}
    void size(int w,int h){
        if(w<16 || h<16 || w>8192 || h>8192)return;
        worker.post(()->{
            if(closed)return;
            // Sender display callbacks may arrive after the new SPS. Only SPS controls
            // decoder reconfiguration, atomically with the matching IDR/parameter sets.
            listener.size(w,h);
        });
    }
    // Coalesce worker wakeups as well as bounding compressed data.
    private final java.util.concurrent.atomic.AtomicBoolean kickQueued=new java.util.concurrent.atomic.AtomicBoolean();
    private final Runnable kick=this::kickPump;
    private void kickPump(){kickQueued.set(false);if(!closed && !pumping){pumping=true;worker.post(pump);}}
    void frame(byte[] data,long timeNs){
        if(closed || !frames.offer(data,timeNs))return;
        if(kickQueued.compareAndSet(false,true))worker.post(kick);
    }
    private final Runnable pump=new Runnable(){public void run(){
        if(closed){pumping=false;return;}
        try{
            for(int n=0;n<4;n++){
                if(pending!=null && pending.generation!=frames.generation())pending=null;
                if(pending==null)pending=frames.poll();
                if(pending==null)break;
                if(codec==null || configuredGeneration!=pending.generation){releaseCodec();createCodec(pending);}
                drain();
                int index=codec.dequeueInputBuffer(0);if(index<0)break;
                ByteBuffer input=codec.getInputBuffer(index);
                if(input==null || input.capacity()<pending.data.length)throw new IllegalStateException("영상 프레임이 디코더 입력보다 큽니다.");
                input.clear();input.put(pending.data);latency.queued(pending,System.nanoTime());
                codec.queueInputBuffer(index,0,pending.data.length,pending.timeUs,0);pending=null;
            }
            if(codec!=null)drain();
            String report=latency.report(System.nanoTime(),frames.dropped);if(report!=null)Log.i("SidePad-AirPlay",report);
        }catch(Exception error){
            Log.e("SidePad-AirPlay","decode failed: "+decoderName,error);
            if(!decoderName.isEmpty())failedDecoders.add(decoderName);
            releaseCodec();frames.recover();pending=null;
            listener.error("영상 디코더를 복구하고 있습니다. 화면이 돌아오지 않으면 아이폰에서 다시 연결해 주세요.");
        }
        if(!closed && (codec!=null || pending!=null || frames.peek()!=null))worker.postDelayed(this,3);else pumping=false;
    }};
    private void createCodec(AirPlayFrames.Frame frame) throws Exception {
        String mime="video/avc";
        int width=frame.format.width,height=frame.format.height;
        ArrayList<MediaCodecInfo> candidates=new ArrayList<>();
        for(MediaCodecInfo candidate:new MediaCodecList(MediaCodecList.ALL_CODECS).getCodecInfos()){
            if(candidate.isEncoder() || candidate.getName().contains("secure") || failedDecoders.contains(candidate.getName()))continue;
            try{if(candidate.getCapabilitiesForType(mime).getVideoCapabilities().isSizeSupported(width,height))candidates.add(candidate);}catch(IllegalArgumentException ignored){}
        }
        candidates.sort(Comparator.comparingInt((MediaCodecInfo candidate)->{
            boolean hw=Build.VERSION.SDK_INT>=29?candidate.isHardwareAccelerated():!(candidate.getName().startsWith("OMX.google.") || candidate.getName().startsWith("c2.android."));
            return hw?0:1;
        }));
        for(MediaCodecInfo candidate:candidates){
            MediaCodec next=null;
            try{
                next=MediaCodec.createByCodecName(candidate.getName());
                MediaFormat format=MediaFormat.createVideoFormat(mime,width,height);
                format.setInteger(MediaFormat.KEY_MAX_INPUT_SIZE,AirPlayFrames.MAX_FRAME);
                format.setInteger(MediaFormat.KEY_PRIORITY,0);
                format.setInteger(MediaFormat.KEY_FRAME_RATE,60);
                format.setByteBuffer("csd-0",ByteBuffer.wrap(frame.sps));
                format.setByteBuffer("csd-1",ByteBuffer.wrap(frame.pps));
                if(Build.VERSION.SDK_INT>=30 && candidate.getCapabilitiesForType(mime).isFeatureSupported(MediaCodecInfo.CodecCapabilities.FEATURE_LowLatency))format.setInteger(MediaFormat.KEY_LOW_LATENCY,1);
                next.configure(format,surface,null,0);
                next.setOnFrameRenderedListener((decoder,pts,nano)->{
                    if(!closed && decoder==codec)latency.rendered(pts,System.nanoTime());
                    if(!closed && decoder==codec && !firstFrame){firstFrame=true;Log.i("SidePad-AirPlay","first-frame-rendered pts="+pts);listener.rendered();}
                },worker);
                next.start();codec=next;firstFrame=false;decoderName=candidate.getName();configuredGeneration=frame.generation;
                listener.size(frame.format.visibleWidth,frame.format.visibleHeight);
                Log.i("SidePad-AirPlay","decoder="+candidate.getName()+" coded="+width+"x"+height+" visible="+frame.format.visibleWidth+"x"+frame.format.visibleHeight+" generation="+frame.generation);return;
            }catch(Exception error){if(next!=null)try{next.release();}catch(Exception ignored){}}
        }
        throw new IllegalStateException("지원되는 H.264 디코더가 없습니다.");
    }
    private void drain(){
        int latest=-1;long latestPts=0;
        for(int n=0;n<32;n++){
            int index=codec.dequeueOutputBuffer(info,0);
            if(index==MediaCodec.INFO_OUTPUT_FORMAT_CHANGED){
                MediaFormat format=codec.getOutputFormat();
                int w=format.getInteger(MediaFormat.KEY_WIDTH),h=format.getInteger(MediaFormat.KEY_HEIGHT);
                if(format.containsKey("crop-right") && format.containsKey("crop-left"))w=format.getInteger("crop-right")-format.getInteger("crop-left")+1;
                if(format.containsKey("crop-bottom") && format.containsKey("crop-top"))h=format.getInteger("crop-bottom")-format.getInteger("crop-top")+1;
                listener.size(w,h);
            }else if(index>=0){latency.ready(info.presentationTimeUs,System.nanoTime());if(latest>=0){codec.releaseOutputBuffer(latest,false);latency.discard(latestPts);}latest=index;latestPts=info.presentationTimeUs;}
            else break;
        }
        if(latest>=0)codec.releaseOutputBuffer(latest,true);
    }
    void reset(){worker.post(()->{releaseCodec();frames.clear();pending=null;});}
    void close(){closed=true;worker.removeCallbacksAndMessages(null);worker.post(()->{releaseCodec();frames.clear();thread.quitSafely();});}
    private void releaseCodec(){
        if(codec!=null){try{codec.stop();}catch(Exception ignored){}try{codec.release();}catch(Exception ignored){}codec=null;}firstFrame=false;configuredGeneration=-1;latency.reset();
    }
}
