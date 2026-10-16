package studio.prxs.paddisplay;

import java.util.Arrays;
import java.util.LinkedHashMap;

/** Receiver component timings only. Neither the iPhone capture delay nor input-to-photon latency. */
final class AirPlayLatency {
    private static final class Sample {long received,queued;Sample(long r,long q){received=r;queued=q;}}
    private final LinkedHashMap<Long,Sample> samples=new LinkedHashMap<>();
    private final double[] queueMs=new double[120],readyMs=new double[120],renderMs=new double[120];
    private int readyCount,renderCount;
    private long since=System.nanoTime();
    void queued(AirPlayFrames.Frame frame,long now){
        if(samples.size()>=128)samples.remove(samples.keySet().iterator().next());
        samples.put(frame.timeUs,new Sample(frame.receivedNs,now));
    }
    void ready(long pts,long now){Sample s=samples.get(pts);if(s==null)return;int i=readyCount++%120;queueMs[i]=(s.queued-s.received)/1e6;readyMs[i]=(now-s.received)/1e6;}
    void rendered(long pts,long now){Sample s=samples.remove(pts);if(s!=null)renderMs[renderCount++%120]=(now-s.received)/1e6;}
    void discard(long pts){samples.remove(pts);}
    String report(long now,long dropped){
        if(now-since<2_000_000_000L)return null;
        String result=String.format(java.util.Locale.ROOT,"receiver-latency queue-p95=%.1fms received-to-ready-p95=%.1fms received-to-render-callback-p95=%.1fms rendered-fps=%.1f dropped=%d",p95(queueMs,readyCount),p95(readyMs,readyCount),p95(renderMs,renderCount),renderCount*1e9/(now-since),dropped);
        readyCount=renderCount=0;since=now;return result;
    }
    private static double p95(double[] values,int count){if(count==0)return -1;double[] sorted=Arrays.copyOf(values,Math.min(count,values.length));Arrays.sort(sorted);return sorted[(int)Math.ceil(sorted.length*.95)-1];}
    void reset(){samples.clear();readyCount=renderCount=0;since=System.nanoTime();}
}
