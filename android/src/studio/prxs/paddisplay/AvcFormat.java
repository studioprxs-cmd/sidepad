package studio.prxs.paddisplay;

/** H.264 SPS geometry. Coded macroblock dimensions and visible crop are distinct. */
final class AvcFormat {
    final int width,height,visibleWidth,visibleHeight;
    AvcFormat(int w,int h,int vw,int vh){width=w;height=h;visibleWidth=vw;visibleHeight=vh;}
    static AvcFormat parse(byte[] nal){
        try{
            int offset=nal.length>3 && nal[2]==1?3:4;
            if(nal.length<=offset || (nal[offset]&31)!=7)return null;
            byte[] rbsp=new byte[nal.length];int count=0,zeros=0;
            for(int i=offset+1;i<nal.length;i++){
                int value=nal[i]&255;
                if(zeros>=2 && value==3){zeros=0;continue;}
                rbsp[count++]=nal[i];zeros=value==0?zeros+1:0;
            }
            Bits bits=new Bits(rbsp,count);int profile=bits.read(8);bits.read(8);bits.read(8);bits.ue();
            int chroma=1,separate=0;
            if(profile==100 || profile==110 || profile==122 || profile==244 || profile==44 || profile==83 || profile==86 || profile==118 || profile==128 || profile==138 || profile==139 || profile==134 || profile==135){
                chroma=bits.ue();if(chroma>3)return null;
                if(chroma==3)separate=bits.read(1);
                bits.ue();bits.ue();bits.read(1);
                if(bits.read(1)==1)for(int i=0;i<(chroma==3?12:8);i++)if(bits.read(1)==1){
                    int last=8,next=8;
                    for(int j=0;j<(i<6?16:64);j++){if(next!=0)next=(last+bits.se()+256)&255;last=next==0?last:next;}
                }
            }
            bits.ue();int order=bits.ue();
            if(order==0)bits.ue();else if(order==1){bits.read(1);bits.se();bits.se();int n=bits.ue();if(n>256)return null;for(int i=0;i<n;i++)bits.se();}else if(order!=2)return null;
            bits.ue();bits.read(1);int wm=bits.ue(),hm=bits.ue(),frame=bits.read(1);
            if(wm>511 || hm>511)return null;
            if(frame==0)bits.read(1);bits.read(1);
            int left=0,right=0,top=0,bottom=0;
            if(bits.read(1)==1){left=bits.ue();right=bits.ue();top=bits.ue();bottom=bits.ue();}
            int type=separate==1?0:chroma;
            int x=type==0 || type==3?1:2;
            int y=(type==1?2:1)*(2-frame);
            int w=(wm+1)*16,h=(hm+1)*16*(2-frame);
            long vw=(long)w-(long)x*(left+(long)right),vh=(long)h-(long)y*(top+(long)bottom);
            if(w>8192 || h>8192 || vw<1 || vh<1)return null;
            return new AvcFormat(w,h,(int)vw,(int)vh);
        }catch(IllegalArgumentException error){return null;}
    }
    private static final class Bits {
        final byte[] bytes;final int limit;int at;
        Bits(byte[] bytes,int count){this.bytes=bytes;limit=count*8;}
        int read(int n){if(n<0 || n>31 || at+n>limit)throw new IllegalArgumentException("truncated SPS");int v=0;while(n-->0){v=(v<<1)|((bytes[at>>3]>>(7-(at&7)))&1);at++;}return v;}
        int ue(){int n=0;while(read(1)==0)if(++n>29)throw new IllegalArgumentException("invalid Golomb code");return ((1<<n)-1)+read(n);}
        int se(){int v=ue();return (v&1)==0?-(v/2):(v+1)/2;}
    }
}
