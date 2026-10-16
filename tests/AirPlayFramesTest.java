package studio.prxs.paddisplay;

public final class AirPlayFramesTest {
    private static byte[] hex(String value){byte[] d=new byte[value.length()/2];for(int i=0;i<d.length;i++)d[i]=(byte)Integer.parseInt(value.substring(i*2,i*2+2),16);return d;}
    private static final byte[] PORTRAIT=hex("000000016764001facd94080089e225c0440000003004000000f03c60c6580");
    private static final byte[] LANDSCAPE=hex("0000000167640028acd94078071f9b0110000003001000000303c0f1831960");
    private static byte[] nal(int type){return type==7?PORTRAIT:new byte[]{0,0,0,1,(byte)type,7,8,9};}
    private static void check(boolean b,String message){if(!b)throw new AssertionError(message);}
    public static void main(String[] args){
        AirPlayFrames queue=new AirPlayFrames();
        check(!queue.offer(nal(1),1000),"must not decode a P-frame without parameter sets and an IDR");
        check(!queue.offer(nal(7),1000),"cache SPS");check(!queue.offer(nal(8),1000),"cache PPS");
        check(queue.offer(nal(5),123000),"accept first IDR");
        check(queue.peek().timeUs==123 && queue.peek().data.length==PORTRAIT.length+16,"parameter sets and timestamp retained");
        queue.remove();check(queue.offer(nal(1),124000),"accept dependent picture after IDR");
        for(int i=0;i<30;i++)queue.offer(nal(1),125000+i);
        check(queue.size()<=AirPlayFrames.MAX_FRAMES,"bounded under a slow decoder");
        check(!queue.offer(nal(1),200000),"overflow must wait for a new keyframe");
        check(queue.offer(nal(5),201000),"recover at next IDR with cached parameter sets");
        check(queue.peek().data.length==PORTRAIT.length+16,"recovery IDR includes parameter sets");
        queue.clear();check(!queue.offer(nal(5),300000),"new session must not inherit parameter sets");
        check(!queue.offer(new byte[AirPlayFrames.MAX_FRAME+1],0),"reject oversized frame");
        check(!queue.offer(new byte[]{0,0,1},0),"truncated start code");
        queue.offer(java.util.Arrays.copyOfRange(PORTRAIT,1,PORTRAIT.length),0);queue.offer(new byte[]{0,0,1,8,8},0);
        check(queue.offer(new byte[]{0,0,1,5,9},0),"three-byte Annex B start codes supported");
        AvcFormat portrait=AvcFormat.parse(PORTRAIT),landscape=AvcFormat.parse(LANDSCAPE);
        check(portrait!=null && portrait.width==512 && portrait.height==1088 && portrait.visibleWidth==498 && portrait.visibleHeight==1080,"portrait coded padding and crop");
        check(landscape!=null && landscape.width==1920 && landscape.height==896 && landscape.visibleWidth==1920 && landscape.visibleHeight==886,"landscape coded padding and crop");
        check(AvcFormat.parse(new byte[]{0,0,1,7,0})==null,"truncated SPS rejected");
        queue.clear();queue.offer(PORTRAIT,0);queue.offer(nal(8),0);queue.offer(nal(5),0);
        AirPlayFrames.Frame old=queue.peek();
        queue.offer(LANDSCAPE,1000);
        check(queue.size()==0 && queue.generation()!=old.generation,"rotation discards stale portrait frames atomically");
        check(!queue.offer(nal(1),2000),"rotation waits for a matching IDR");
        check(queue.offer(nal(5),3000),"rotation restarts at new format IDR");
        AirPlayFrames.Frame next=queue.poll();
        check(next.format.visibleWidth==1920 && next.format.visibleHeight==886,"frame carries the matching SPS geometry");
        check(next.generation==queue.generation() && queue.size()==0,"atomic dequeue");
        long generation=queue.generation();queue.offer(LANDSCAPE,4000);
        check(queue.generation()==generation,"identical SPS must not restart decoder");
        System.out.println("AirPlay frame queue: passed (rotation, SPS crop, format generations, keyframe recovery)");
    }
}
