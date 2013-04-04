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

@implementation AppDelegate

- (void)dealloc
{
    [super dealloc];
}


int count = 0;

int refflags = 0;
int pcmdflags =  (1 << 1) | 1;

- (void) sendToDrone: (id) what {
    char buf[512];
    
    const char * fmt = "AT*REF=%d,%d\rAT*PCMD=%d,%d,%d,%d,%d,%d\r";
    
    refflags = (flying << 9) | (emergencyBit << 8);
    sprintf(buf,fmt,count,refflags,count+1,pcmdflags,*(int*)&roll,*(int*)&pitch,*(int*)&power,*(int*)&yaw);
    
    NSData * data = [NSData dataWithBytes:buf length:strlen(buf)+1];
    NSData * destinationAddressData = [NSData dataWithBytes:&ataddr length:sizeof(ataddr)];
    
    if(count/2 % 50 == 0) {//roughly every second, see what we are printing
        NSLog(@"%s\n",buf);
        struct sockaddr_in myself;
        initAddress(&myself, "127.0.0.1", 5557);
        NSData * destinationAddressData2 = [NSData dataWithBytes:&myself length:sizeof(struct sockaddr_in)];
        if(CFSocketSendData(navsocket,(CFDataRef)destinationAddressData2, (CFDataRef) data, 0))
            NSLog(@"send error");
    }
    
    
    int result = CFSocketSendData(atsocket,(CFDataRef)destinationAddressData, (CFDataRef) data, 0);
    count+=2;
    if (result != 0) {
        NSLog(@"BROKEN\n");
    }
}

void initAddress(struct sockaddr_in * addr, const char * ip, int port) {
    memset(addr,0,sizeof(struct sockaddr_in));
    addr->sin_len = sizeof(struct sockaddr_in);
    addr->sin_family = AF_INET;
    addr->sin_port = htons(port);
    inet_aton(ip,&addr->sin_addr);
}

void socketDataReceive(CFSocketRef s, CFSocketCallBackType type, CFDataRef address, const void *data, void *info) {
    char buf[512];
    int sock = CFSocketGetNative(s);
    int addrlen;
    struct sockaddr_in addr;
    if (recvfrom(sock, buf, 512, 0, &addr, &addrlen) == -1) {
        NSLog(@"recvfrom error");
    }
    NSLog(@"SOCKET DATA: %s\n",buf);

}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
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
    //TODO: navport is NOT CORRECT
#define NAVPORT 5557

    navsocket = CFSocketCreate(kCFAllocatorDefault, PF_INET, SOCK_DGRAM, IPPROTO_UDP, kCFSocketReadCallBack, socketDataReceive, NULL);
    assert(socket);
    struct sockaddr_in myself;
    initAddress(&myself, "127.0.0.1", NAVPORT);
    myself.sin_addr.s_addr = htonl(INADDR_ANY);
    int nativenavsocket = CFSocketGetNative(navsocket);
    if(bind(nativenavsocket,&myself,sizeof(struct sockaddr_in))) {
        NSLog(@"failed to bind");
    }
    
    initAddress(&navaddr, "192.168.1.1", NAVPORT);
    
    CFRunLoopSourceRef rlr = CFSocketCreateRunLoopSource(NULL, navsocket, 0);
    CFRunLoopAddSource(CFRunLoopGetCurrent(), rlr, kCFRunLoopDefaultMode);
    
    [NSTimer scheduledTimerWithTimeInterval:0.02
                                 target:self
                               selector:@selector(sendToDrone:)
                               userInfo:nil
                                repeats:YES];
    
}

@end
