package studio.prxs.paddisplay;

import android.content.Context;
import android.net.nsd.NsdManager;
import android.net.nsd.NsdServiceInfo;
import android.net.wifi.WifiManager;
import android.os.Handler;
import android.os.Looper;
import java.util.ArrayList;
import java.util.Map;

/** The platform publishes the engine's TXT records; no second mDNS stack is needed. */
final class AirPlayDiscovery {
    interface Listener { void registered(String name); void failed(String message); }
    private final NsdManager manager;
    private final Handler main=new Handler(Looper.getMainLooper());
    private final ArrayList<NsdManager.RegistrationListener> registrations=new ArrayList<>();
    private WifiManager.MulticastLock multicast;
    private boolean closed;
    AirPlayDiscovery(Context context) {
        manager=(NsdManager)context.getSystemService(Context.NSD_SERVICE);
        WifiManager wifi=(WifiManager)context.getApplicationContext().getSystemService(Context.WIFI_SERVICE);
        if(wifi!=null){multicast=wifi.createMulticastLock("SidePad-AirPlay");multicast.setReferenceCounted(false);multicast.acquire();}
    }
    void register(String name,String type,int port,Map<String,String> records,Listener listener) {
        main.post(()->{
            if(closed)return;
            NsdServiceInfo info=new NsdServiceInfo();info.setServiceName(name);info.setServiceType(type);info.setPort(port);
            if(records!=null)for(Map.Entry<String,String> entry:records.entrySet())info.setAttribute(entry.getKey(),entry.getValue());
            NsdManager.RegistrationListener registration=new NsdManager.RegistrationListener(){
                public void onServiceRegistered(NsdServiceInfo value){
                    main.post(()->{if(closed)unregister(this);else listener.registered(value.getServiceName());});
                }
                public void onRegistrationFailed(NsdServiceInfo value,int code){
                    main.post(()->{if(!closed)listener.failed("기기 검색을 시작하지 못했습니다 ("+code+").");});
                }
                public void onServiceUnregistered(NsdServiceInfo value){}
                public void onUnregistrationFailed(NsdServiceInfo value,int code){}
            };
            registrations.add(registration);
            try{manager.registerService(info,NsdManager.PROTOCOL_DNS_SD,registration);}
            catch(RuntimeException error){listener.failed("기기 검색을 시작하지 못했습니다.");}
        });
    }
    private void unregister(NsdManager.RegistrationListener registration){try{manager.unregisterService(registration);}catch(RuntimeException ignored){}}
    void close(){
        main.post(()->{
            if(closed)return;closed=true;
            for(NsdManager.RegistrationListener registration:registrations)unregister(registration);
            registrations.clear();
            if(multicast!=null && multicast.isHeld())multicast.release();multicast=null;
        });
    }
}
