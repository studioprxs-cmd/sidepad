package studio.prxs.paddisplay;
import java.io.*;
import java.util.Arrays;

public final class CursorPacketsTest {
    private static void check(boolean value){if(!value)throw new AssertionError();}
    private static byte[] packet(int type,byte[] data)throws Exception{
        ByteArrayOutputStream bytes=new ByteArrayOutputStream();DataOutputStream out=new DataOutputStream(bytes);
        out.writeByte(type);out.writeInt(data.length);out.write(data);return bytes.toByteArray();
    }
    private static byte[] pos(int value){byte[] data=new byte[17];data[0]=(byte)value;return data;}
    private static byte[] join(byte[]... packets)throws Exception{
        ByteArrayOutputStream out=new ByteArrayOutputStream();for(byte[] packet:packets)out.write(packet);return out.toByteArray();
    }
    private static final class Partial extends ByteArrayInputStream {
        Partial(byte[] bytes,int visible){super(bytes);count=visible;}
        void reveal(){count=buf.length;}
    }
    public static void main(String[] args)throws Exception{
        byte[] a=packet(4,pos(1)),b=packet(4,pos(2)),image=packet(6,new byte[12]);
        CursorPackets.Latest latest=CursorPackets.readLatest(new DataInputStream(new ByteArrayInputStream(join(a,image,b))));
        check(latest.positions==2 && latest.position[0]==2 && latest.image.length==12);
        for(int visible:new int[]{a.length+3,a.length+5,a.length+12}){
            Partial partial=new Partial(join(a,b),visible);DataInputStream input=new DataInputStream(new BufferedInputStream(partial));
            latest=CursorPackets.readLatest(input);check(latest.positions==1 && latest.position[0]==1);
            partial.reveal();latest=CursorPackets.readLatest(input);check(latest.positions==1 && latest.position[0]==2);
        }
        byte[][] many=new byte[130][];Arrays.fill(many,a);
        DataInputStream input=new DataInputStream(new ByteArrayInputStream(join(many)));
        check(CursorPackets.readLatest(input).positions==64);
        check(CursorPackets.readLatest(input).positions==64);
        check(CursorPackets.readLatest(input).positions==2);
        try{CursorPackets.readLatest(new DataInputStream(new ByteArrayInputStream(packet(4,new byte[18]))));throw new AssertionError();}
        catch(IOException expected){}
        System.out.println("Cursor packet tests passed (latest position, shape preservation, partial packets, bounded bursts)");
    }
}
