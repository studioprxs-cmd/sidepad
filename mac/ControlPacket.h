#include <sys/socket.h>
#include <arpa/inet.h>
#include <errno.h>

static BOOL PDRead(int fd, void *bytes, size_t length) {
    size_t offset=0;
    while (offset<length) { ssize_t n=recv(fd,(char *)bytes+offset,length-offset,0);
        if(n<0 && errno==EINTR)continue;
        if(n<=0)return NO;
        offset+=(size_t)n;
    }
    return YES;
}
static NSDictionary *PDReadControlPacket(int fd,uint8_t *type) {
    uint8_t header[5];
    if(!PDRead(fd,header,sizeof(header)))return nil;
    if(type)*type=header[0];
    uint32_t length;memcpy(&length,header+1,4);length=ntohl(length);
    if(length<2 || length>16384)return nil;
    NSMutableData *data=[NSMutableData dataWithLength:length];
    if(!PDRead(fd,data.mutableBytes,length))return nil;
    id value=[NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [value isKindOfClass:NSDictionary.class] ? value : nil;
}
static NSDictionary *PDReadControl(int fd,uint8_t expectedType) {
    uint8_t type=0;NSDictionary *json=PDReadControlPacket(fd,&type);
    return type==expectedType ? json : nil;
}
