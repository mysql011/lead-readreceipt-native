#import <Foundation/Foundation.h>
#import "Headers/GRRTypes.h"

@interface GRRSettings : NSObject

+ (instancetype)shared;

@property (nonatomic, assign, readonly) BOOL enabled;
@property (nonatomic, assign, readonly) BOOL allowReport;
@property (nonatomic, assign, readonly) NSTimeInterval refreshInterval;
@property (nonatomic, copy, readonly) NSString *backendURL;
@property (nonatomic, copy, readonly) NSString *apiToken;
@property (nonatomic, assign, readonly) BOOL captureHostLog;

- (void)reload;
- (void)setEnabled:(BOOL)value;
- (void)setAllowReport:(BOOL)value;
- (void)setRefreshInterval:(NSTimeInterval)value;
- (void)setBackendURL:(NSString *)value;
- (void)setAPIToken:(NSString *)value;
- (void)setCaptureHostLog:(BOOL)value;
- (BOOL)isReportingAllowed;

@end
