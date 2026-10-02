package studio.prxs.paddisplay;

/** Direct touch with deferred clicks, drag, two-finger scroll, and cancel-safe button state. */
final class TouchGesture {
    interface Sink { void send(int action,float x,float y,float dx,float dy); }
    static final int DOWN=0,UP=1,MOVE=2,CANCEL=3,POINTER_DOWN=5,POINTER_UP=6;
    private static final int IDLE=0,SINGLE=1,DRAG=2,SCROLL=3,BLOCKED=4;
    private final Sink sink;
    private final float slop;
    private int state=IDLE,primary=-1,width=1,height=1;
    private float startX,startY,lastX,lastY,centerX,centerY;
    TouchGesture(float slop,Sink sink){this.slop=slop;this.sink=sink;}
    private float nx(float x){return Math.max(0,Math.min(1,x/width));}
    private float ny(float y){return Math.max(0,Math.min(1,y/height));}
    private void emit(int action,float x,float y){sink.send(action,nx(x),ny(y),0,0);}
    void cancel(){if(state==DRAG)emit(4,lastX,lastY);state=IDLE;primary=-1;}
    void block(){cancel();state=BLOCKED;}
    void event(int action,int changed,int[] ids,float[] xs,float[] ys,int w,int h,boolean blocked){
        width=Math.max(1,w);height=Math.max(1,h);
        if(action==CANCEL){cancel();return;}
        if(action==DOWN){
            cancel();
            if(blocked || ids.length!=1){state=BLOCKED;return;}
            primary=ids[0];startX=lastX=xs[0];startY=lastY=ys[0];state=SINGLE;
            emit(0,lastX,lastY);return;
        }
        if(blocked){block();if(action==UP)cancel();return;}
        if(action==UP){
            if(ids.length>0){lastX=xs[0];lastY=ys[0];}
            if(state==SINGLE){emit(2,lastX,lastY);emit(3,lastX,lastY);}
            else if(state==DRAG){emit(1,lastX,lastY);emit(3,lastX,lastY);}
            state=IDLE;primary=-1;return;
        }
        if(state==IDLE || state==BLOCKED)return;
        if(ids.length>2){block();return;}
        if(action==POINTER_UP){
            if(state==SCROLL || (changed>=0 && changed<ids.length && ids[changed]==primary))block();
            return;
        }
        if(ids.length==2){
            float cx=(xs[0]+xs[1])*.5f,cy=(ys[0]+ys[1])*.5f;
            if(state!=SCROLL){
                if(state==DRAG)emit(3,lastX,lastY);
                state=SCROLL;centerX=cx;centerY=cy;emit(0,cx,cy);return;
            }
            if(action==MOVE){
                float dx=(cx-centerX)/width,dy=(cy-centerY)/height;
                if(dx!=0 || dy!=0)sink.send(6,nx(cx),ny(cy),dx,dy);
                centerX=cx;centerY=cy;
            }
            return;
        }
        int index=-1;for(int i=0;i<ids.length;i++)if(ids[i]==primary)index=i;
        if(index<0){block();return;}
        if(action==MOVE && (state==SINGLE || state==DRAG)){
            lastX=xs[index];lastY=ys[index];
            float dx=lastX-startX,dy=lastY-startY;
            if(state==SINGLE && dx*dx+dy*dy>slop*slop){emit(2,startX,startY);state=DRAG;}
            if(state==DRAG)emit(1,lastX,lastY);
        }
    }
}
