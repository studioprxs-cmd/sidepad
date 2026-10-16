package studio.prxs.paddisplay;

import java.io.ByteArrayOutputStream;
import java.util.ArrayDeque;

/** Bounded compressed-frame queue. Recover after overflow only at a complete GOP boundary. */
final class AirPlayFrames {
    static final int MAX_FRAME=4*1024*1024, MAX_BYTES=8*1024*1024, MAX_FRAMES=12;
    static final class Frame {
        final byte[] data,sps,pps;final long timeUs,receivedNs,generation;
        final AvcFormat format;
        Frame(byte[] data,long timeUs,long receivedNs,long generation,AvcFormat format,byte[] sps,byte[] pps){this.data=data;this.timeUs=timeUs;this.receivedNs=receivedNs;this.generation=generation;this.format=format;this.sps=sps;this.pps=pps;}
    }
    private final ArrayDeque<Frame> queue=new ArrayDeque<>();
    private byte[] sps,pps;
    private AvcFormat format;
    private long generation;
    private int bytes;
    private boolean waiting=true;
    long dropped;

    synchronized boolean offer(byte[] data,long timeNs) {
        return offer(data,timeNs,System.nanoTime());
    }
    synchronized boolean offer(byte[] data,long timeNs,long receivedNs) {
        if(data==null || data.length<4 || data.length>MAX_FRAME)return false;
        boolean idr=false,picture=false;
        for(int i=0;i<data.length-3;) {
            int prefix=startCode(data,i);
            if(prefix==0){i++;continue;}
            int header=i+prefix;if(header>=data.length)break;
            int type=data[header]&31;
            int end=header+1;
            while(end<data.length && startCode(data,end)==0)end++;
            if(type==7){
                byte[] next=nal(data,i,end);AvcFormat parsed=next.length<=65536?AvcFormat.parse(next):null;
                if(parsed==null)return false;
                if(!java.util.Arrays.equals(sps,next)){recover();generation++;sps=next;format=parsed;}
            }
            if(type==8){byte[] next=nal(data,i,end);if(next.length>65536)return false;if(!java.util.Arrays.equals(pps,next)){recover();generation++;pps=next;}}
            if(type==5)idr=true;
            if(type==1 || type==5)picture=true;
            i=end;
        }
        if(!picture)return false; // Keep parameter sets, submit them together with the next IDR.
        if(queue.size()>=MAX_FRAMES || bytes+data.length>MAX_BYTES)recover();
        if(waiting && (!idr || sps==null || pps==null)){dropped++;return false;}
        byte[] frame=data;
        if(idr && sps!=null && pps!=null){
            ByteArrayOutputStream out=new ByteArrayOutputStream(sps.length+pps.length+data.length);
            out.write(sps,0,sps.length);out.write(pps,0,pps.length);out.write(data,0,data.length);frame=out.toByteArray();
            if(frame.length>MAX_FRAME){dropped++;return false;}
        }
        if(bytes+frame.length>MAX_BYTES)recover();
        if(waiting && !idr){dropped++;return false;}
        if(idr)waiting=false;
        queue.addLast(new Frame(frame,timeNs/1000,receivedNs,generation,format,sps,pps));bytes+=frame.length;return true;
    }
    private static byte[] nal(byte[] data,int start,int end){return java.util.Arrays.copyOfRange(data,start,end);}
    private static int startCode(byte[] d,int i) {
        if(i+2>=d.length || d[i]!=0 || d[i+1]!=0)return 0;
        if(d[i+2]==1)return 3;
        return i+3<d.length && d[i+2]==0 && d[i+3]==1?4:0;
    }
    synchronized Frame peek(){return queue.peekFirst();}
    synchronized void remove(){Frame f=queue.pollFirst();if(f!=null)bytes-=f.data.length;}
    synchronized Frame poll(){Frame f=queue.pollFirst();if(f!=null)bytes-=f.data.length;return f;}
    synchronized void recover(){dropped+=queue.size();queue.clear();bytes=0;waiting=true;}
    synchronized long generation(){return generation;}
    synchronized void clear(){recover();generation++;sps=null;pps=null;format=null;}
    synchronized int size(){return queue.size();}
}
