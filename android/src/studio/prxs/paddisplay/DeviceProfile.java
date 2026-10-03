package studio.prxs.paddisplay;

import android.media.MediaCodecInfo;
import android.media.MediaCodecList;
import android.os.Build;
import android.view.Display;
import org.json.JSONArray;
import org.json.JSONObject;
import java.util.LinkedHashSet;

final class DeviceProfile {
    static Display.Mode preferredMode(Display display) {
        Display.Mode current=display.getMode(),best=current;
        for(Display.Mode mode:display.getSupportedModes()) {
            if(mode.getPhysicalWidth()!=current.getPhysicalWidth() || mode.getPhysicalHeight()!=current.getPhysicalHeight())continue;
            if(mode.getRefreshRate()<=120.5f && (best.getRefreshRate()>120.5f || mode.getRefreshRate()>best.getRefreshRate()))best=mode;
        }
        return best;
    }
    static boolean supports(MediaCodecInfo info,int width,int height,int fps) {
        if(info.isEncoder() || info.getName().contains("secure"))return false;
        try {
            MediaCodecInfo.CodecCapabilities caps=info.getCapabilitiesForType("video/avc");
            boolean high=false;
            for(MediaCodecInfo.CodecProfileLevel level:caps.profileLevels)
                if(level.profile==MediaCodecInfo.CodecProfileLevel.AVCProfileHigh)high=true;
            return high && caps.getVideoCapabilities().areSizeAndRateSupported(width,height,fps);
        } catch(IllegalArgumentException ignored){return false;}
    }
    static JSONObject capabilities(Display display,double requestedAspect) throws Exception {
        Display.Mode panel=display.getMode();
        int nativeWidth=Math.max(panel.getPhysicalWidth(),panel.getPhysicalHeight());
        int nativeHeight=Math.min(panel.getPhysicalWidth(),panel.getPhysicalHeight());
        double aspect=requestedAspect>0 ? requestedAspect : (double)nativeWidth/nativeHeight;
        if(!Double.isFinite(aspect) || aspect<.25 || aspect>5)throw new Exception("화면 비율을 확인할 수 없습니다.");
        MediaCodecInfo[] codecs=new MediaCodecList(MediaCodecList.ALL_CODECS).getCodecInfos();
        LinkedHashSet<String> seen=new LinkedHashSet<>();JSONArray modes=new JSONArray();
        for(int limit:new int[]{4096,2560,1920,1472,1280,960}) {
            int width=Math.min(nativeWidth,limit)&~1;
            int height=((int)Math.round(width/aspect))&~1;
            if(height>4096){height=4096;width=((int)(height*aspect))&~1;}
            for(int alignment:new int[]{2,16}) {
                int w=width/alignment*alignment,h=height/alignment*alignment;
                if(w<320 || h<240 || !seen.add(w+"x"+h))continue;
                int maxFPS=0;
                for(MediaCodecInfo info:codecs) {
                    boolean hardware=Build.VERSION.SDK_INT>=29 ? info.isHardwareAccelerated() :
                        !(info.getName().startsWith("OMX.google.") || info.getName().startsWith("c2.android."));
                    if(!hardware)continue;
                    if(supports(info,w,h,60))maxFPS=60;
                    else if(maxFPS<30 && supports(info,w,h,30))maxFPS=30;
                }
                if(maxFPS>0)modes.put(new JSONObject().put("width",w).put("height",h).put("maxFPS",maxFPS));
            }
        }
        if(modes.length()==0)throw new Exception("이 패드에서 지원하는 H.264 화면 모드를 찾지 못했습니다.");
        return new JSONObject().put("protocol",3).put("model",Build.MODEL).put("nativeWidth",nativeWidth)
            .put("nativeHeight",nativeHeight).put("panelHz",preferredMode(display).getRefreshRate()).put("modes",modes);
    }
}
