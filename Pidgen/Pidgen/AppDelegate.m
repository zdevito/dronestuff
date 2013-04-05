//
//  AppDelegate.m
//  Pidgen
//
//  Created by Zachary DeVito on 4/2/13.
//  Copyright (c) 2013 Zachary DeVito. All rights reserved.
//

#import "AppDelegate.h"
#import <Foundation/Foundation.h>
#import <IOKit/hid/IOHIDLib.h>
#include <sys/types.h> 
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
//#include "navdata_common.h"


#define NAVDATA_HEADER  0x55667788


typedef struct {
  uint32_t    header;			/* NAVDATA_HEADER */
  uint32_t    state;    /*!< Bit mask built from def_ardrone_state_mask_t */
  uint32_t    sequence;         /*!< Sequence number, incremented for each sent packet */
  uint32_t    vision_defined;
  char options[];
} __attribute__((packed)) NavHeader;


#define ARDRONE_STATE_ELEMS(_) \
_(DRONE_FLY_MASK, 0) /*!< FLY MASK : (0) ardrone is landed, (1) ardrone is flying */ \
_(VIDEO_MASK, 1) /*!< VISION MASK : (0) vision disable, (1) vision enable */ \
_(VISION_MASK, 2) /*!< VISION MASK : (0) vision disable, (1) vision enable */ \
_(CONTROL_MASK, 3) /*!< CONTROL ALGO : (0) euler angles control, (1) angular speed control */ \
_(ALTITUDE_MASK, 4) /*!< ALTITUDE CONTROL ALGO : (0) altitude control inactive (1) altitude control active */ \
_(USER_FEEDBACK_START, 5) /*!< USER feedback : Start button state */ \
_(COMMAND_MASK, 6) /*!< Control command ACK : (0) None, (1) one received */ \
_(FW_FILE_MASK, 7) /* Firmware file is good (1) */ \
_(FW_VER_MASK, 8) /* Firmware update is newer (1) */ \
_(NAVDATA_DEMO_MASK, 10) /*!< Navdata demo : (0) All navdata, (1) only navdata demo */ \
_(NAVDATA_BOOTSTRAP, 11) /*!< Navdata bootstrap : (0) options sent in all or demo mode, (1) no navdata options sent */ \
_(MOTORS_MASK, 12) /*!< Motors status : (0) Ok, (1) Motors problem */ \
_(COM_LOST_MASK, 13) /*!< Communication Lost : (1) com problem, (0) Com is ok */ \
_(VBAT_LOW, 15) /*!< VBat low : (1) too low, (0) Ok */ \
_(USER_EL, 16) /*!< User Emergency Landing : (1) User EL is ON, (0) User EL is OFF*/ \
_(TIMER_ELAPSED, 17) /*!< Timer elapsed : (1) elapsed, (0) not elapsed */ \
_(ANGLES_OUT_OF_RANGE, 19) /*!< Angles : (0) Ok, (1) out of range */ \
_(ULTRASOUND_MASK, 21) /*!< Ultrasonic sensor : (0) Ok, (1) deaf */ \
_(CUTOUT_MASK, 22) /*!< Cutout system detection : (0) Not detected, (1) detected */ \
_(PIC_VERSION_MASK, 23) /*!< PIC Version number OK : (0) a bad version number, (1) version number is OK */ \
_(ATCODEC_THREAD_ON, 24) /*!< ATCodec thread ON : (0) thread OFF (1) thread ON */ \
_(NAVDATA_THREAD_ON, 25) /*!< Navdata thread ON : (0) thread OFF (1) thread ON */ \
_(VIDEO_THREAD_ON, 26) /*!< Video thread ON : (0) thread OFF (1) thread ON */ \
_(ACQ_THREAD_ON, 27) /*!< Acquisition thread ON : (0) thread OFF (1) thread ON */ \
_(CTRL_WATCHDOG_MASK, 28) /*!< CTRL watchdog : (1) delay in control execution (> 5ms), (0) control is well scheduled */ \
_(ADC_WATCHDOG_MASK, 29) /*!< ADC Watchdog : (1) delay in uart2 dsr (> 5ms), (0) uart2 is good */ \
_(COM_WATCHDOG_MASK, 30) /*!< Communication Watchdog : (1) com problem, (0) Com is ok */ \
_(EMERGENCY_MASK, 31) /*!< Emergency landing : (0) no emergency, (1) emergency */

typedef enum {
    #define MAKE_ENUM(name,bit) ND_##name = 1 << bit,
    ARDRONE_STATE_ELEMS(MAKE_ENUM)
    #undef MAKE_ENUM
    NUM_BITS
} StateMask;

#define OPTION_TAGS(_) \
_(DEMO,0) \
_(TIME,1) \
_(RAW_MEASURES,2) \
_(PHYS_MEASURES,3) \
_(GYROS_OFFSETS,4) \
_(EULER_ANGLES,5) \
_(REFERENCES,6) \
_(TRIMS,7) \
_(RC_REFERENCES,8) \
_(PWM,9) \
_(ALTITUDE,10) \
_(VISION_RAW,11) \
_(VISION_OF,12) \
_(VISION,13) \
_(VISION_PERF,14) \
_(TRACKERS_SEND,15) \
_(VISION_DETECT,16) \
_(WATCHDOG,17) \
_(ADC_DATA_FRAME,18) \
_(VIDEO_STREAM,19) \
_(GAMES,20) \
_(PRESSURE_RAW,21) \
_(MAGNETO,22) \
_(WIND_SPEED,23) \
_(KALMAN_PRESSURE,24) \
_(HDVIDEO_STREAM,25) \
_(WIFI,26) \
_(ZIMMU_3000,27) \
_(CKS,65535)

typedef enum {
#define MAKE_ENUM(name,num) OP_##name = num,
    OPTION_TAGS(MAKE_ENUM)
    NUM_OPTIONS
} OptionTag;

typedef float float9[9];
typedef float float3[3];

#define DEMO_STRUCT(_) \
_(uint16_t,d,fly_state) \
_(uint16_t,d,ctrl_state) \
_(uint32_t,d,vbat_flying_percentage) \
_(float,f,theta) \
_(float,f,phi) \
_(float,f,psi) \
_(int32_t,d,altitude) \
_(float,f,vx) \
_(float,f,vy) \
_(float,f,vz) \
_(uint32_t,d,num_frames) \
_(float9,p,detection_camera_rot) \
_(float3,p,detection_camera_trans) \
_(uint32_t,d,detection_tag_index) \
_(uint32_t,d,detection_camera_type) \
_(float9,p,drone_camera_rot) \
_(float3,p,drone_camera_trans) \


typedef struct {
#define MAKESTRUCT(typ,fmt,name) typ name;

DEMO_STRUCT(MAKESTRUCT)

#undef MAKESTRUCT
} DemoState;





CFSocketRef atsocket;
struct sockaddr_in ataddr;

CFSocketRef navsocket;
struct sockaddr_in navaddr;

void gamepadWasAdded(void* inContext, IOReturn inResult,
                     void* inSender, IOHIDDeviceRef device);
void gamepadWasRemoved(void* inContext, IOReturn inResult, 
                       void* inSender, IOHIDDeviceRef device);
void gamepadAction(void* inContext, IOReturn inResult, 
                   void* inSender, IOHIDValueRef value);
 
void gamepadWasAdded(void* inContext, IOReturn inResult,
                     void* inSender, IOHIDDeviceRef device) {
    NSLog(@"Gamepad was plugged in: %@", device);
}
 
void gamepadWasRemoved(void* inContext, IOReturn inResult, 
                       void* inSender, IOHIDDeviceRef device) {
    NSLog(@"Gamepad was unplugged");
}

float roll = 0.0;
float pitch = 0.0;
float yaw = 0.0;
float power = 0.0;
int emergencyBit = 0;
int flying = 0;
uint32_t droneState;
DemoState demoState;

void gamepadAction(void* inContext, IOReturn inResult, 
                   void* inSender, IOHIDValueRef value) {
    //NSLog(@"Gamepad talked!");
    IOHIDElementRef element = IOHIDValueGetElement(value);
     
    int usagePage = IOHIDElementGetUsagePage(element);
    int usage = IOHIDElementGetUsage(element);
    long elementValue = IOHIDValueGetIntegerValue(value);
    
    NSLog(@"%x %x %lx",usagePage,usage,elementValue);
    switch (usagePage) {
        case 0x1: /*generic page*/
            switch(usage) {
                case 0x30: /*left pad x */
                    roll = 2.0 * (elementValue/255.0) - 1;
                    break;
                case 0x31: /*left pad y */
                    pitch = 2.0 * (elementValue/255.0) - 1;
                    break;
                case 0x32: /* right pad x */
                    yaw = 2.0 * (elementValue/255.0) - 1;
                    break;
                case 0x35: /* right pad y */
                    power = -(2.0 * (elementValue/255.0) - 1);
                    break;
                default:
                    NSLog(@"Unknown?");
                    break;
            }
            NSLog(@"%f %f %f %f\n",roll,pitch,yaw,power);
            break;
        case 0x9: /*buttons*/
            switch(usage) {
                case 0x0a: /* 10 */
                    emergencyBit = (int)elementValue;
                    if(emergencyBit)
                        flying = 0;
                    break;
                case 0x09: /* 9 */
                    if (elementValue == 1)
                        flying = !flying;
                    break;
            }
        default:
            NSLog(@"Unknown Type?");
            break;
    }
    
}


void PrintDemoDiff(DemoState * old, DemoState * cur) {
    assert(sizeof(DemoState) + 4 == 148);
    #define PRINT_DEMO(typ,fmt,field) if(cur->field != old->field && #fmt[0] != 'p') NSLog(@"%s = %" #fmt ";", #field, cur->field);
    DEMO_STRUCT(PRINT_DEMO)
    #undef PRINT_DEMO
}
void PrintStateDiff(lastState,curState) {
    #define DO_PRINT(flag,bit) if( (curState & (1 << bit)) != (lastState & (1 << bit)))  NSLog(@"flag %s = %d", #flag, (curState & (1 << bit)) != 0);
    ARDRONE_STATE_ELEMS(DO_PRINT)
    #undef DO_PRINT
}


@implementation AppDelegate

- (void)dealloc
{
    [super dealloc];
}


int count = 0;

int refflags = 0;
int pcmdflags =  (1 << 1) | 1;


int NewSeq() {
    return ++count;
}

char sendbuf[512];
int sendbuflen = 1; /* includes null*/
int nsends = 0;
void SendData(const char * fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    sendbuflen += vsprintf(sendbuf + sendbuflen - 1, fmt,ap);
    va_end(ap);
    nsends++;
}

DemoState oldDemoState;

void FlushData() {
    assert(sendbuflen == strlen(sendbuf) + 1);
    NSData * data = [NSData dataWithBytes:sendbuf length:sendbuflen];
    NSData * destinationAddressData = [NSData dataWithBytes:&ataddr length:sizeof(ataddr)];
    
    if(CFSocketSendData(atsocket,(CFDataRef)destinationAddressData, (CFDataRef) data, 0) ) {
        NSLog(@"BROKEN\n");
    }
    if(count/2 % 50 == 0 || nsends > 1) {//roughly every second, see what we are printing
        NSLog(@"%s\n",sendbuf);
        PrintDemoDiff(&oldDemoState, &demoState);
        memcpy(&oldDemoState,&demoState,sizeof(DemoState));
    }
    sendbuf[0] = '\0';
    sendbuflen = 1;
    nsends = 0;
}



/* run every 20ms to keep drone alive */
- (void) updateState: (id) what {
    const char * fmt = "AT*REF=%d,%d\rAT*PCMD=%d,%d,%d,%d,%d,%d\r";
    refflags = (flying << 9) | (emergencyBit << 8);
    int seq1 = NewSeq();
    int seq2 = NewSeq();
    SendData(fmt,seq1,refflags,seq2,pcmdflags,*(int*)&roll,*(int*)&pitch,*(int*)&power,*(int*)&yaw);
    
    FlushData();
    
    const char * somedata = "1";
    NSData * data2 = [NSData dataWithBytes:somedata length:1];
    NSData * destinationAddressData2 = [NSData dataWithBytes:&navaddr length:sizeof(struct sockaddr_in)];
    if( 0 != CFSocketSendData(navsocket,(CFDataRef)destinationAddressData2, (CFDataRef) data2, 0)) {
        NSLog(@"Error sending data to nav port");
    }
    
}

void initAddress(struct sockaddr_in * addr, const char * ip, int port) {
    memset(addr,0,sizeof(struct sockaddr_in));
    addr->sin_len = sizeof(struct sockaddr_in);
    addr->sin_family = AF_INET;
    addr->sin_port = htons(port);
    inet_aton(ip,&addr->sin_addr);
}

typedef struct {
    uint16_t tag;
    uint16_t size;
    char data[];
} NavOption;



void socketDataReceive(CFSocketRef s, CFSocketCallBackType type, CFDataRef address, const void *data, void *info) {
    char buf[512];
    int sock = CFSocketGetNative(s);
    int addrlen;
    struct sockaddr_in addr;
    ssize_t len = recvfrom(sock, buf, 512, 0, &addr, &addrlen);
    if (len == -1) {
        NSLog(@"recvfrom error");
    }
    //NSLog(@"DATA %d",len);
    
    
    NavHeader * header = (NavHeader*) buf;
    
    if(header->header != NAVDATA_HEADER) {
        NSLog(@"INCORRECT HEADER \n");
        return;
    }
    
    PrintStateDiff(droneState, header->state);
    droneState = header->state;
    
    char * op = header->options;
    while(op < buf + len) {
        NavOption * navop = (NavOption*) op;
        //NSLog(@"id = %d, size = %d\n",navop->tag,navop->size);
        
        #if 0
        switch(navop->tag) {
            #define GENSWITCH(name,id) case id: NSLog(@"Option: %s",#name); break;
            OPTION_TAGS(GENSWITCH)
            default: break;
        }
        #endif
        switch(navop->tag) {
            case OP_DEMO: {
                DemoState * demo = (DemoState*) navop->data;
                memcpy(&demoState,demo,sizeof(DemoState));
            } break;
            default:
                break;
        }
        
        
        op += navop->size;
    }
    
    
    if(droneState & ND_NAVDATA_BOOTSTRAP) {
        NSLog(@"BOOTSTRAP");
        SendData("AT*CONFIG=%d,\"general:navdata_demo\",\"TRUE\"\r",NewSeq());
    }
#if 0
    //this is in the spec but doesn't appear necessary...
    if((droneState & ND_COMMAND_MASK) != 0 && len == 24) {
        NSLog(@"ACKED");
        SendData("AT*CTRL=0\r");
    }
#endif
    
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    sendbuf[0] = '\0';
    bzero(&demoState, sizeof(DemoState));
    // Insert code here to initialize your application
    //get a HID manager reference
    IOHIDManagerRef hidManager = IOHIDManagerCreate(kCFAllocatorDefault, 
                                    kIOHIDOptionsTypeNone);
     
    //define the device to search for, via usage page and usage key
    NSMutableDictionary* criterion = [[NSMutableDictionary alloc] init];
    [criterion setObject: [NSNumber numberWithInt: kHIDPage_GenericDesktop] 
                  forKey: (NSString*)CFSTR(kIOHIDDeviceUsagePageKey)];
    [criterion setObject: [NSNumber numberWithInt: kHIDUsage_GD_Joystick] 
                  forKey: (NSString*)CFSTR(kIOHIDDeviceUsageKey)];
     
    //search for the device
    IOHIDManagerSetDeviceMatching(hidManager, 
                                  (CFDictionaryRef)criterion);
     
    //register our callback functions
    IOHIDManagerRegisterDeviceMatchingCallback(hidManager, gamepadWasAdded, 
                                               (void*)self);
    IOHIDManagerRegisterDeviceRemovalCallback(hidManager, gamepadWasRemoved, 
                                              (void*)self);
    IOHIDManagerRegisterInputValueCallback(hidManager, gamepadAction, 
                                           (void*)self);
     
    //scedule our HIDManager with the current run loop, so that we
    //are able to recieve events from the hardware.
    IOHIDManagerScheduleWithRunLoop(hidManager, CFRunLoopGetCurrent(), 
                                    kCFRunLoopDefaultMode);
     
    //open the HID manager, so that it can start routing events
    //to our callbacks.
    IOHIDManagerOpen(hidManager, kIOHIDOptionsTypeNone);
    NSLog(@"INIT");
    
    atsocket = CFSocketCreate(kCFAllocatorDefault, PF_INET, SOCK_DGRAM, IPPROTO_UDP, 0, NULL, NULL);
    assert(socket);
    
    initAddress(&ataddr,"192.168.1.1", 5556);
    
    //TODO: set callback
#define NAVPORT 5554

    navsocket = CFSocketCreate(kCFAllocatorDefault, PF_INET, SOCK_DGRAM, IPPROTO_UDP, kCFSocketReadCallBack, socketDataReceive, NULL);
    assert(socket);
    struct sockaddr_in myself;
    initAddress(&myself, "0.0.0.0", NAVPORT);
    int nativenavsocket = CFSocketGetNative(navsocket);

  // set group
    struct ip_mreq mreq;
    bzero(&mreq,sizeof(struct ip_mreq));
  
    mreq.imr_multiaddr.s_addr = inet_addr("224.1.1.1");
    mreq.imr_interface.s_addr = htonl(INADDR_ANY);
     
   
    if(setsockopt(nativenavsocket, IPPROTO_IP, IP_ADD_MEMBERSHIP, &mreq, sizeof(mreq))) {
        NSLog(@"setsockopts failed");
    }
    
    if(bind(nativenavsocket,&myself,sizeof(struct sockaddr_in))) {
        NSLog(@"failed to bind");
    }
    
    
    initAddress(&navaddr, "192.168.1.1", NAVPORT);
    
   
    
    CFRunLoopSourceRef rlr = CFSocketCreateRunLoopSource(NULL, navsocket, 0);
    CFRunLoopAddSource(CFRunLoopGetCurrent(), rlr, kCFRunLoopDefaultMode);
    
    
    [NSTimer scheduledTimerWithTimeInterval:0.02
                                 target:self
                               selector:@selector(updateState:)
                               userInfo:nil
                                repeats:YES];
    
}

@end
