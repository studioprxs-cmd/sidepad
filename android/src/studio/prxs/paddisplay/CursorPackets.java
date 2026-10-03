package studio.prxs.paddisplay;

import java.io.DataInputStream;
import java.io.IOException;

/** Drain complete queued positions without waiting for a partial next packet. */
final class CursorPackets {
    static final class Latest {
        byte[] position,image;
        int positions;
    }
    private static void validate(int type,int length) throws IOException {
        if(!((type==4 && length==17) || (type==6 && length>8 && length<=512*1024)))
            throw new IOException("잘못된 커서 패킷");
    }
    private static void body(DataInputStream input,int type,int length,Latest latest) throws IOException {
        byte[] data=new byte[length];input.readFully(data);
        if(type==4){latest.position=data;latest.positions++;}else latest.image=data;
    }
    static Latest readLatest(DataInputStream input) throws IOException {
        Latest latest=new Latest();
        int type=input.readUnsignedByte(),length=input.readInt();validate(type,length);
        body(input,type,length,latest);
        // Bound work per display update; preserve packet framing across partial reads.
        for(int i=1;i<64 && input.markSupported() && input.available()>=5;i++){
            input.mark(5);type=input.readUnsignedByte();length=input.readInt();validate(type,length);
            if(input.available()<length){input.reset();break;}
            body(input,type,length,latest);
        }
        return latest;
    }
}
