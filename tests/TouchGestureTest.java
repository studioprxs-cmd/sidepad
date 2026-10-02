package studio.prxs.paddisplay;
import java.util.*;
public final class TouchGestureTest {
    static final List<float[]> events=new ArrayList<>();
    static TouchGesture fresh(){events.clear();return new TouchGesture(8,(a,x,y,dx,dy)->events.add(new float[]{a,x,y,dx,dy}));}
    static void one(TouchGesture g,int action,float x,float y,boolean blocked){g.event(action,0,new int[]{7},new float[]{x},new float[]{y},1000,800,blocked);}
    static void two(TouchGesture g,int action,float y){g.event(action,1,new int[]{7,12},new float[]{100,300},new float[]{y,y},1000,800,false);}
    static void actions(int... wanted){if(events.size()!=wanted.length)throw new AssertionError("length "+events.size()+" != "+wanted.length);for(int i=0;i<wanted.length;i++)if(events.get(i)[0]!=wanted[i])throw new AssertionError("action "+i);}
    public static void main(String[] args){
        TouchGesture g=fresh();one(g,0,100,200,false);one(g,1,100,200,false);actions(0,2,3);
        if(events.get(1)[1]!=.1f || events.get(1)[2]!=.25f)throw new AssertionError("mapping");
        g=fresh();one(g,0,100,200,false);one(g,2,104,203,false);actions(0);
        one(g,2,150,250,false);one(g,1,180,280,false);actions(0,2,1,1,3);
        g=fresh();one(g,0,100,200,false);two(g,5,200);two(g,2,150);two(g,6,150);one(g,1,100,150,false);actions(0,0,6);
        if(events.get(2)[4]!=-.0625f)throw new AssertionError("scroll distance/direction");
        g=fresh();one(g,0,100,200,false);one(g,2,150,250,false);g.block();one(g,1,150,250,false);actions(0,2,1,4);
        g=fresh();one(g,0,100,200,true);one(g,2,150,250,false);one(g,1,150,250,false);actions();
        one(g,0,100,200,false);one(g,1,100,200,false);actions(0,2,3);
        g=fresh();one(g,0,100,200,false);one(g,2,150,250,false);two(g,5,250);two(g,2,200);two(g,6,200);one(g,1,100,200,false);actions(0,2,1,3,0,6);
        g=fresh();one(g,0,100,200,false);one(g,3,100,200,false);one(g,1,100,200,false);actions(0);
        System.out.println("PASS: tap, slop, drag, scroll without accidental clicks, pen takeover, cancellation, gesture recovery");
    }
}
