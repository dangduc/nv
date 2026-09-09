#import <Cocoa/Cocoa.h>
@class NVApplicationController, NotationController;

extern NSString * const NVBackupStatusDidChangeNotification;

// Main-thread coordinator. The worker receives immutable checkpoint bytes only.
@interface NVBackupController : NSObject {
    NVApplicationController *applicationController; // application owns this controller
    NotationController *library;
    NSString *libraryIdentifier;
    NSTimer *timer;
    NSOperationQueue *worker;
    NSMutableDictionary *librarySettings;
    NSDate *nextAttempt;
    NSTimeInterval nextAttemptDelay;
    NSString *latestError;
    NSString *latestNotice;
    NSUInteger contextGeneration;
    BOOL busy;
    BOOL stopped;
    BOOL retentionPending;
    long long lastRetentionDay;
}
- (id)initWithApplicationController:(NVApplicationController *)controller;
- (void)setLibrary:(NotationController *)newLibrary;
- (void)stop;
- (NSString *)libraryIdentifier;
- (NSDictionary *)settings;
- (BOOL)setSettings:(NSDictionary *)settings error:(NSError **)error;
- (NSString *)statusText;
- (NSURL *)destinationURL;
- (BOOL)isBusy;
- (BOOL)hasLibrary;
// Explicit date supports deterministic scheduling checks without sleeping.
- (void)checkForBackupAtDate:(NSDate *)date;
- (IBAction)backupNow:(id)sender;
- (IBAction)chooseDestination:(id)sender;
- (IBAction)showBackupsInFinder:(id)sender;
- (IBAction)restoreBackup:(id)sender;
- (IBAction)deleteUnencryptedBackups:(id)sender;
@end
