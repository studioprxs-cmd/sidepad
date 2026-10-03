package studio.prxs.paddisplay;

public final class StreamStatsTest {
    private static void check(boolean value){if(!value)throw new AssertionError();}
    public static void main(String[] args){
        StreamStats stats=new StreamStats(1_000_000_000L);
        stats.received();stats.submitted();
        check(!stats.hasRendered());
        stats.decoded(1_000_000L,1_012_000_000L);
        // Delayed callbacks and driver timestamps do not alter measured decoder timing.
        stats.rendered(1_000_000L,1_000_000_000L);
        StreamStats.Sample sample=stats.sample(2_000_000_000L);
        check(sample.rendered==1 && sample.fps==1 && sample.decodeMs==12);
        sample=stats.sample(3_000_000_000L);
        check(stats.hasRendered() && sample.fps==0 && sample.decodeMs==-1);
        stats.dropped();stats.received();stats.submitted();
        stats.decoded(3_000_000L,2_900_000_000L);
        stats.rendered(3_000_000L,2_900_000_000L);
        sample=stats.sample(4_000_000_000L);
        check(sample.rendered==2 && sample.dropped==1 && sample.decodeMs==-1);
        System.out.println("Receiver display acknowledgement, decoder timing and idle metrics tests passed");
    }
}
