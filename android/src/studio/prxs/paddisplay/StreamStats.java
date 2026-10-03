package studio.prxs.paddisplay;

// Keep decoder timing independent of frame-render callbacks, which some drivers batch
// or report with the input presentation timestamp instead of a useful elapsed time.
final class StreamStats {
    private long received,submitted,dropped,rendered,latencyNanos,latencyCount,lastSample,lastRendered;
    StreamStats(long now){lastSample=now;}
    synchronized void received(){received++;}
    synchronized void submitted(){submitted++;}
    synchronized void dropped(){dropped++;}
    synchronized boolean hasRendered(){return rendered>0;}
    synchronized void rendered(long presentationTimeUs,long renderNanoTime){
        rendered++;
    }
    synchronized void decoded(long presentationTimeUs,long outputNanoTime){
        long latency=outputNanoTime-presentationTimeUs*1000;
        if(latency>=0 && latency<=5_000_000_000L){latencyNanos+=latency;latencyCount++;}
    }
    synchronized Sample sample(long now){
        long elapsed=now-lastSample;
        double fps=elapsed>0 ? (rendered-lastRendered)*1_000_000_000.0/elapsed : 0;
        double decodeMs=latencyCount>0 ? latencyNanos/(latencyCount*1_000_000.0) : -1;
        Sample sample=new Sample(received,submitted,dropped,rendered,Math.min(240,fps),decodeMs);
        lastSample=now;lastRendered=rendered;latencyNanos=latencyCount=0;
        return sample;
    }
    static final class Sample {
        final long received,submitted,dropped,rendered;
        final double fps,decodeMs;
        Sample(long received,long submitted,long dropped,long rendered,double fps,double decodeMs){
            this.received=received;this.submitted=submitted;this.dropped=dropped;this.rendered=rendered;
            this.fps=fps;this.decodeMs=decodeMs;
        }
    }
}
