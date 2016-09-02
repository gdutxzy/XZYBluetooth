//
//  BTLECentralViewController.m
//  XZYBluetooth
//
//  Created by mac on 16/9/2.
//  Copyright © 2016年 mac. All rights reserved.
//

#import "BTLECentralViewController.h"
#import <CoreBluetooth/CoreBluetooth.h>

@interface BTLECentralViewController ()<CBCentralManagerDelegate, CBPeripheralDelegate>
@property (weak, nonatomic) IBOutlet UITextView *receivedTextView;

@property (weak, nonatomic) IBOutlet UITextView *sendTextView;


@property (strong, nonatomic) CBCentralManager      *centralManager;
@property (strong, nonatomic) CBPeripheral          *discoveredPeripheral;
@property (strong,nonatomic) CBCharacteristic * characteristic;
@property (strong, nonatomic) NSMutableData         *data;
@end

@implementation BTLECentralViewController
- (IBAction)senddata:(UIButton *)sender {
    
    [self writeCharacteristic:self.discoveredPeripheral characteristic:self.characteristic value:[self.sendTextView.text dataUsingEncoding:NSUTF8StringEncoding]];
}


- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = @"centralManager";

    // 建立一个中心对象
    _centralManager = [[CBCentralManager alloc] initWithDelegate:self queue:nil];
    
    _data = [[NSMutableData alloc] init];
}




- (void)viewWillDisappear:(BOOL)animated
{
    // 中央管理器停止扫描设备
    [self.centralManager stopScan];
    [super viewWillDisappear:animated];
}



#pragma mark - Central Methods
// 设备支持蓝牙并且处于打开状态
- (void)centralManagerDidUpdateState:(CBCentralManager *)central
{
    if (central.state != CBCentralManagerStatePoweredOn) {
        return;
    }
    NSLog(@">>>>>");
    [self scan];
}

- (void)scan
{
    // 搜索一个制定的服务 如果第一个参数为nil表示搜索所有服务
    [self.centralManager scanForPeripheralsWithServices:@[[CBUUID UUIDWithString:TRANSFER_SERVICE_UUID]]
                                                options:@{ CBCentralManagerScanOptionAllowDuplicatesKey : @YES }];
    
    
}

// 周边在寻找的时候被发现 中央的代理会收到以下回调
- (void)centralManager:(CBCentralManager *)central didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:(NSDictionary *)advertisementData RSSI:(NSNumber *)RSSI
{
    // 信号强度
    if (RSSI.integerValue > -15 || RSSI.integerValue < -35) {
        return;
    }
    
    if (self.discoveredPeripheral != peripheral) {
        self.discoveredPeripheral = peripheral;
        // 连接外设
        [self.centralManager connectPeripheral:peripheral options:nil];
    }
}

// 连接外设失败
- (void)centralManager:(CBCentralManager *)central didFailToConnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error
{
    [self cleanup];
}


// 连接外设成功
- (void)centralManager:(CBCentralManager *)central didConnectPeripheral:(CBPeripheral *)peripheral
{
    NSLog(@"Peripheral Connected");
    
    // 中央管理器停止扫描设备
    [self.centralManager stopScan];
    NSLog(@"Scanning stopped");
    
    // 清空数据
    [self.data setLength:0];
    
    peripheral.delegate = self;
    
    // Search only for services that match our UUID
    // 请求周边寻找服务
    [peripheral discoverServices:@[[CBUUID UUIDWithString:TRANSFER_SERVICE_UUID]]];
}


// 发现服务调用
- (void)peripheral:(CBPeripheral *)peripheral didDiscoverServices:(NSError *)error
{
    if (error) {
        NSLog(@"Error discovering services: %@", [error localizedDescription]);
        [self cleanup];
        return;
    }
    
    //
    for (CBService *service in peripheral.services) {
        [peripheral discoverCharacteristics:@[[CBUUID UUIDWithString:TRANSFER_CHARACTERISTIC_UUID]] forService:service];
    }
}


/** The Transfer characteristic was discovered.
 *  Once this has been found, we want to subscribe to it, which lets the peripheral know we want the data it contains
 */
- (void)peripheral:(CBPeripheral *)peripheral didDiscoverCharacteristicsForService:(CBService *)service error:(NSError *)error
{
    // Deal with errors (if any)
    if (error) {
        NSLog(@"Error discovering characteristics: %@", [error localizedDescription]);
        [self cleanup];
        return;
    }
    
    // Again, we loop through the array, just in case.
    for (CBCharacteristic *characteristic in service.characteristics) {
        
        // And check if it's the right one
        if ([characteristic.UUID isEqual:[CBUUID UUIDWithString:TRANSFER_CHARACTERISTIC_UUID]]) {
            //            [peripheral readValueForCharacteristic:characteristic];
//            [self writeCharacteristic:peripheral characteristic:characteristic value:[@"haha" dataUsingEncoding:NSUTF8StringEncoding]];
            // If it is, subscribe to it
            self.characteristic = characteristic;
            [peripheral setNotifyValue:YES forCharacteristic:characteristic];
        }
    }
    
    // Once this is complete, we just need to wait for the data to come in.
}


/** This callback lets us know more data has arrived via notification on the characteristic
 */
- (void)peripheral:(CBPeripheral *)peripheral didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error
{
    if (error) {
        NSLog(@"Error discovering characteristics: %@", [error localizedDescription]);
        return;
    }
    
    NSString *stringFromData = [[NSString alloc] initWithData:characteristic.value encoding:NSUTF8StringEncoding];
    
    // Have we got everything we need?
    if ([stringFromData isEqualToString:@"EOM"]) {
        
        // We have, so show the data,
        [self.receivedTextView setText:[[NSString alloc] initWithData:self.data encoding:NSUTF8StringEncoding]];
        
        // Cancel our subscription to the characteristic
        [peripheral setNotifyValue:NO forCharacteristic:characteristic];
        
        // and disconnect from the peripehral
        [self.centralManager cancelPeripheralConnection:peripheral];
    }
    
    // Otherwise, just add the data on to what we already have
    [self.data appendData:characteristic.value];
    
    // Log it
    NSLog(@"Received: %@", stringFromData);
}


/** The peripheral letting us know whether our subscribe/unsubscribe happened or not
 */
- (void)peripheral:(CBPeripheral *)peripheral didUpdateNotificationStateForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error
{
    if (error) {
        NSLog(@"Error changing notification state: %@", error.localizedDescription);
    }
    
    // Exit if it's not the transfer characteristic
    if (![characteristic.UUID isEqual:[CBUUID UUIDWithString:TRANSFER_CHARACTERISTIC_UUID]]) {
        return;
    }
    
    // Notification has started
    if (characteristic.isNotifying) {
        NSLog(@"Notification began on %@", characteristic);
    }
    
    // Notification has stopped
    else {
        // so disconnect from the peripheral
        NSLog(@"Notification stopped on %@.  Disconnecting", characteristic);
        [self.centralManager cancelPeripheralConnection:peripheral];
    }
}


/** Once the disconnection happens, we need to clean up our local copy of the peripheral
 */
- (void)centralManager:(CBCentralManager *)central didDisconnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error
{
    NSLog(@"Peripheral Disconnected");
    self.discoveredPeripheral = nil;
    
    // We're disconnected, so start scanning again
    [self scan];
}


/** Call this when things either go wrong, or you're done with the connection.
 *  This cancels any subscriptions if there are any, or straight disconnects if not.
 *  (didUpdateNotificationStateForCharacteristic will cancel the connection if a subscription is involved)
 */
- (void)cleanup
{
    // Don't do anything if we're not connected
    if (self.discoveredPeripheral.state != CBPeripheralStateConnected) {
        return;
    }
    
    // See if we are subscribed to a characteristic on the peripheral
    if (self.discoveredPeripheral.services != nil) {
        for (CBService *service in self.discoveredPeripheral.services) {
            if (service.characteristics != nil) {
                for (CBCharacteristic *characteristic in service.characteristics) {
                    if ([characteristic.UUID isEqual:[CBUUID UUIDWithString:TRANSFER_CHARACTERISTIC_UUID]]) {
                        if (characteristic.isNotifying) {
                            // It is notifying, so unsubscribe
                            [self.discoveredPeripheral setNotifyValue:NO forCharacteristic:characteristic];
                            
                            // And we're done.
                            return;
                        }
                    }
                }
            }
        }
    }
    
    // 断开连接
    [self.centralManager cancelPeripheralConnection:self.discoveredPeripheral];
}




/** Adds the 'Done' button to the title bar
 */
- (void)textViewDidBeginEditing:(UITextView *)textView
{
    // We need to add this manually so we have a way to dismiss the keyboard
    UIBarButtonItem *rightButton = [[UIBarButtonItem alloc] initWithTitle:@"Done" style:UIBarButtonItemStyleDone target:self action:@selector(dismissKeyboard)];
    self.navigationItem.rightBarButtonItem = rightButton;
}


//写数据
-(void)writeCharacteristic:(CBPeripheral *)peripheral
            characteristic:(CBCharacteristic *)characteristic
                     value:(NSData *)value{
    
    //打印出 characteristic 的权限，可以看到有很多种，这是一个NS_OPTIONS，就是可以同时用于好几个值，常见的有read，write，notify，indicate，知知道这几个基本就够用了，前连个是读写权限，后两个都是通知，两种不同的通知方式。
    /*
     typedef NS_OPTIONS(NSUInteger, CBCharacteristicProperties) {
     CBCharacteristicPropertyBroadcast												= 0x01,
     CBCharacteristicPropertyRead													= 0x02,
     CBCharacteristicPropertyWriteWithoutResponse									= 0x04,
     CBCharacteristicPropertyWrite													= 0x08,
     CBCharacteristicPropertyNotify													= 0x10,
     CBCharacteristicPropertyIndicate												= 0x20,
     CBCharacteristicPropertyAuthenticatedSignedWrites								= 0x40,
     CBCharacteristicPropertyExtendedProperties										= 0x80,
     CBCharacteristicPropertyNotifyEncryptionRequired NS_ENUM_AVAILABLE(NA, 6_0)		= 0x100,
     CBCharacteristicPropertyIndicateEncryptionRequired NS_ENUM_AVAILABLE(NA, 6_0)	= 0x200
     };
     
     
     
     */
    NSLog(@"%lu", (unsigned long)characteristic.properties);
    
    
    //只有 characteristic.properties 有write的权限才可以写
    if(characteristic.properties & CBCharacteristicPropertyWrite){
        /*
         最好一个type参数可以为CBCharacteristicWriteWithResponse或type:CBCharacteristicWriteWithResponse,区别是是否会有反馈
         */
        [peripheral writeValue:value forCharacteristic:characteristic type:CBCharacteristicWriteWithResponse];
    }else{
        NSLog(@"该字段不可写！");
    }
    
    
}

/** Finishes the editing */
- (void)dismissKeyboard
{
    [self.view endEditing:YES];
    self.navigationItem.rightBarButtonItem = nil;
}


- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event{
    [super touchesBegan:touches withEvent:event];
    [self.view endEditing:YES];
}


@end
