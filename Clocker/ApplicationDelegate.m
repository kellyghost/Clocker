//  Created by Abhishek Banthia on 11/4/15.
//  Copyright (c) 2015 Abhishek Banthia All rights reserved.
//

// Copyright (c) 2015, Abhishek Banthia
// All rights reserved.
//
// Redistribution and use in source and binary forms, with or without modification,
// are permitted provided that the following conditions are met:
//
// Redistributions of source code must retain the above copyright notice,
// this list of conditions and the following disclaimer.
//
// Redistributions in binary form must reproduce the above copyright notice,
// this list of conditions and the following disclaimer in the documentation and/or
// other materials provided with the distribution.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
// WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
// IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
// INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
// PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
// HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
// OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
// EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

#import "ApplicationDelegate.h"
#import <Fabric/Fabric.h>
#import <Crashlytics/Crashlytics.h>
#import "iRate.h"
#import "CommonStrings.h"
#import "iVersion.h"
#import "CLOnboardingWindowController.h"
#import <FMDB/FMDB.h>
#import "CLTimezoneData.h"
#import "CLTimezoneDataOperations.h"
#import "MoLoginItem/MoLoginItem.h"

@implementation ApplicationDelegate

@synthesize panelController = _panelController;
@synthesize menubarController = _menubarController;

#pragma mark -

- (void)dealloc
{
    [self.panelController removeObserver:self forKeyPath:@"hasActivePanel"];
}

#pragma mark -

void *kContextActivePanel = &kContextActivePanel;

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (context == kContextActivePanel)
    {
        self.menubarController.hasActiveIcon = self.panelController.hasActivePanel;
    }
    else
    {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

+ (void)initialize
{
    //Configure iRate
    [iRate sharedInstance].useAllAvailableLanguages = YES;
    [iVersion sharedInstance].useAllAvailableLanguages = YES;
    [[iRate sharedInstance] setVerboseLogging:NO];
    [[iVersion sharedInstance] setVerboseLogging:NO];
    [iRate sharedInstance].promptForNewVersionIfUserRated = YES;
}

#pragma mark - NSApplicationDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
//     [self setupDatabase];
    
    NSNumber *opened = [[NSUserDefaults standardUserDefaults] objectForKey:@"noOfTimes"];
    if (opened == nil)
    {
        [self getLocalTimezoneObject];
        NSInteger noOfTimes = opened.integerValue + 1;
        NSNumber *noOfTime = @(noOfTimes);
        [[NSUserDefaults standardUserDefaults] setObject:noOfTime forKey:@"noOfTimes"];;
        
    }
    
    // Install icon into the menu bar
    self.menubarController = [MenubarController new];
    
    [self initializeDefaults];
    
    /*

    NSString *onboarding = [[NSUserDefaults standardUserDefaults] objectForKey:@"initialLaunch"];
    
    if (onboarding == nil)
    {
        CLOnboardingWindowController *windowController = [CLOnboardingWindowController sharedWindow];
        [windowController showWindow:nil];
        [NSApp activateIgnoringOtherApps:YES];
        [[NSUserDefaults standardUserDefaults] setObject:@"OnboardingDone" forKey:@"initialLaunch"];
    }
    
     */
     
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{ @"NSApplicationCrashOnExceptions": @YES }];
    
    [[Crashlytics sharedInstance] setDebugMode:YES];
    [Fabric with:@[[Crashlytics class]]];
    
}

- (void)getLocalTimezoneObject
{
    CLTimezoneData *currentTimezoneObject = [[CLTimezoneData alloc] init];
    [currentTimezoneObject setIDForTimezone:[NSTimeZone systemTimeZone].name];
    [currentTimezoneObject setLabelForTimezone:[NSTimeZone systemTimeZone].name];
    [currentTimezoneObject setFormattedAddressForTimezone:[NSTimeZone systemTimeZone].name];
    
    CLTimezoneDataOperations *dataOperations = [[CLTimezoneDataOperations alloc] initWithTimezoneData:currentTimezoneObject];
    
    [dataOperations save];
    
}

- (void)setupDatabase
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *applicationSupportDirectory = [[paths firstObject] stringByAppendingPathComponent:@"Clocker"];;
    
    NSError *error = nil;
    
    if(![[NSFileManager defaultManager] createDirectoryAtPath:applicationSupportDirectory withIntermediateDirectories:YES attributes:NULL error:&error]){
        NSLog(@"%@", error);
        return;
    }
    
    NSString *dbPath = [applicationSupportDirectory stringByAppendingPathComponent:@"Timezones.db"];
    FMDatabase *database = [FMDatabase databaseWithPath:dbPath];
    database.crashOnErrors = YES;
    if (![database open]) {
        NSLog(@"%@", database.lastErrorMessage);
        
    }
    else
    {
        NSString *checkIfTableExistsStatement = @"select sql from SQLITE_MASTER where name = 'CLTimezoneData'";
        FMResultSet *checkIfTableExistsResult = [database executeQuery:checkIfTableExistsStatement];
        
        
        if (![checkIfTableExistsResult next])
        {
            NSString *tableCreationStatement = [NSString stringWithFormat:@"create table CLTimezoneData (timezoneNumber INT primary key , timezoneID TEXT, custom_label TEXT, formatted_address TEXT, latitude TEXT, longitude TEXT, is_favourite INT, place_id TEXT,selectionType INT)"];
            
            FMResultSet *resultSet = [database executeQuery:tableCreationStatement];
            
            if ([resultSet next]) {
                [self addObjectsToDatabase:database];
            }
        }
        
        [self addObjectsToDatabase:database];

    }
    
}

- (void)addObjectsToDatabase:(FMDatabase *)database
{
    __block NSInteger emptyTimezones = 0;
    __block NSMutableArray *workingTimezones = [NSMutableArray array];
    
    FMResultSet *resultSet = [database executeQuery:@"SELECT COUNT(*) FROM CLTimezoneData"];
    if ([resultSet next]) {
        
        NSInteger totalCount = [resultSet intForColumnIndex:0];
        
        if (totalCount == 0) {
            
            NSArray *defaultZones = [[NSUserDefaults standardUserDefaults] objectForKey:CLDefaultPreferenceKey];
            
            [defaultZones enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                
                CLTimezoneData *dataObject = [CLTimezoneData getCustomObject:obj];
                
                if ([dataObject isEmpty]) {
                    
                    emptyTimezones++;
                    /*Remove it from the goddarn collection.*/
                }
                else
                {
                    
                    [workingTimezones addObject:dataObject];
                    
                    BOOL success = [database executeUpdate:@"INSERT INTO CLTimezoneData (timezoneNumber, timezoneID, custom_label, formatted_address, latitude, longitude, is_favourite,place_id, selectionType) VALUES (?, ?, ?, ?, ?, ? , ?, ?, ?)", @(idx+1), dataObject.timezoneID, dataObject.customLabel ?: [NSNull null], dataObject.formattedAddress, dataObject.latitude, dataObject.longitude, dataObject.isFavourite, dataObject.place_id,@(dataObject.selectionType)];
                    
                    !success ? NSLog(@"error = %@", [database lastErrorMessage]) : NSLog(@"Data inserted successfully");
                }
                
            }];
        }
        else
        {
            NSLog(@"Count is not zero :%zd", totalCount);
        }
    }
    
    if (emptyTimezones > 0) {
        
        [[NSUserDefaults standardUserDefaults] setObject:nil forKey:CLDefaultPreferenceKey];
        [[NSUserDefaults standardUserDefaults] setObject:nil forKey:@"favouriteTimezone"];
        
        for (id object in workingTimezones)
        {
            CLTimezoneDataOperations *dataOperations = [[CLTimezoneDataOperations alloc] initWithTimezoneData:object];
            [dataOperations save];
        }
        
          [self showErrorMessageForEmptyTimezones];
    }
}

- (void)showErrorMessageForEmptyTimezones
{
    [[NSApplication sharedApplication] activateIgnoringOtherApps:YES];
    NSAlert *alert = [NSAlert new];
    alert.messageText = @"Please add your timezones again 😅";
    alert.informativeText = [NSString stringWithFormat:@"Clocker has encountered an error while reading certain timezones. Please add them again."];
    [alert addButtonWithTitle:@"Okay"];
    NSModalResponse response = [alert runModal];
    if (response == NSModalResponseStop) {
        dispatch_async(dispatch_get_main_queue(), ^{
            
            [self openPreferences];
        });
        
    }
}

- (void)openPreferences
{
    [self.panelController openPreferenceWindowWithValue:YES];
}


- (void)initializeDefaults
{
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    
    NSString *defaultTheme = [userDefaults objectForKey:CLThemeKey];
    if (defaultTheme == nil)
    {
        [userDefaults setObject:@0 forKey:CLThemeKey];
    }
    
    NSNumber *displayFutureSlider = [userDefaults objectForKey:CLDisplayFutureSliderKey];
    if (displayFutureSlider == nil)
    {
        [userDefaults setObject:@0 forKey:CLDisplayFutureSliderKey];
    }
    
    NSNumber *defaultTimeFormat = [userDefaults objectForKey:CL24hourFormatSelectedKey];
    if (defaultTimeFormat == nil)
    {
        [userDefaults setObject:@1 forKey:CL24hourFormatSelectedKey];
    }
    
    NSNumber *relativeDate = [userDefaults objectForKey:CLRelativeDateKey];
    if (relativeDate == nil)
    {
        [userDefaults setObject:@0 forKey:CLRelativeDateKey];
    }
    
    NSNumber *showDayInMenuBar = [userDefaults objectForKey:CLShowDayInMenu];
    if (showDayInMenuBar == nil)
    {
        [userDefaults setObject:@0 forKey:CLShowDayInMenu];
    }
    
    NSNumber *showDateInMenu = [userDefaults objectForKey:CLShowDateInMenu];
    if (showDateInMenu == nil) {
        [userDefaults setObject:@1 forKey:CLShowDateInMenu];
    }
    
    NSNumber *showCityInMenu = [userDefaults objectForKey:CLShowPlaceInMenu];
    if (showCityInMenu == nil)
    {
        [userDefaults setObject:@0 forKey:CLShowPlaceInMenu];
    }
    
    NSNumber *startClockerAtLogin = [userDefaults objectForKey:CLStartAtLogin];
    if (startClockerAtLogin == nil) {
        [userDefaults setObject:@0 forKey:CLStartAtLogin];
    }
    else if([startClockerAtLogin isEqualToNumber:@(1)])
    {
        MOEnableLoginItem(YES);
    }
    
    NSNumber *displayMode = [userDefaults objectForKey:CLShowAppInForeground];
    if (displayMode == nil) {
        [userDefaults setObject:@0 forKey:CLShowAppInForeground];
    }
    
    NSNumber *showSunriseSunsetTime = [userDefaults objectForKey:CLSunriseSunsetTime];
    if (showSunriseSunsetTime == nil) {
        [userDefaults setObject:@1 forKey:CLSunriseSunsetTime];
    }
    
    NSNumber *showSeconds = [userDefaults objectForKey:CLShowSecondsInMenubar];
    if (showSeconds == nil) {
        [userDefaults setObject:@1 forKey:CLShowSecondsInMenubar];
    }

    NSNumber *userFontSize = [userDefaults objectForKey:CLUserFontSizePreference];
    if (userFontSize == nil) {
        [userDefaults setObject:@4 forKey:CLUserFontSizePreference];
    }
    
    
    
    //If mode selected is 1, then show the window when the app starts
    if (displayMode.integerValue == 1)
    {
        [self showFloatingWindow];
    }
}

- (void)showFloatingWindow
{
    self.floatingWindow = [CLFloatingWindowController sharedFloatingWindow];
    [self.floatingWindow showWindow:nil];
    [self.floatingWindow updateTableContent];
    [self.floatingWindow startWindowTimer];
    
    [NSApp activateIgnoringOtherApps:YES];
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender
{
    // Explicitly remove the icon from the menu bar
    self.menubarController = nil;
    return NSTerminateNow;
}

#pragma mark - Actions

- (IBAction)togglePanel:(id)sender
{
    NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
    [dictionary setObject:[[[NSUserDefaults standardUserDefaults] objectForKey:CLThemeKey]  isEqual: @(0)] ? @"Default" : @"Black" forKey:@"Theme"];
    [dictionary setObject:[[[NSUserDefaults standardUserDefaults] objectForKey:CLDisplayFutureSliderKey]  isEqual: @(0)] ? @"Yes" : @"No" forKey:@"Display Future Slider"];
    [dictionary setObject:[[[NSUserDefaults standardUserDefaults] objectForKey:CLShowAppInForeground]  isEqual: @(0)] ? @"Menubar" : @"Floating" forKey:@"Clocker Mode"];
    [dictionary setObject:[[[NSUserDefaults standardUserDefaults] objectForKey:CLRelativeDateKey]  isEqual: @(0)] ? @"Relative" : @"Actual" forKey:@"Relative Date"];
    [dictionary setObject:[[[NSUserDefaults standardUserDefaults] objectForKey:CLShowSecondsInMenubar]  isEqual: @(0)] ? @"Yes" : @"No" forKey:@"Show Seconds in Menubar"];
    [dictionary setObject:[[NSUserDefaults standardUserDefaults] objectForKey:CLUserFontSizePreference] forKey:@"Font Size"];
    [dictionary setObject:[[[NSUserDefaults standardUserDefaults] objectForKey:CLSunriseSunsetTime]  isEqual:@(0)] ? @"Yes" : @"No" forKey:@"Sunrise Sunset"];
    [dictionary setObject:[[[NSUserDefaults standardUserDefaults] objectForKey:CLShowDayInMenu]  isEqual:@(0)] ? @"Yes" : @"No" forKey:@"Show Day in Menu"];
    [dictionary setObject:[[[NSUserDefaults standardUserDefaults] objectForKey:CLShowDateInMenu]  isEqual:@(0)] ? @"Yes" : @"No" forKey:@"Show Date in Menu"];
    [dictionary setObject:[[[NSUserDefaults standardUserDefaults] objectForKey:CLShowPlaceInMenu]  isEqual:@(0)] ? @"Yes" : @"No" forKey:@"Show Place in Menu"];
    
    [Answers logCustomEventWithName:@"openedPanel" customAttributes:dictionary];
    
    
    NSNumber *displayMode = [[NSUserDefaults standardUserDefaults] objectForKey:CLShowAppInForeground];
    
    if (displayMode.integerValue == 1)
    {
        self.floatingWindow = [CLFloatingWindowController sharedFloatingWindow];
        [self.floatingWindow showWindow:nil];
        [self.floatingWindow startWindowTimer];
        [NSApp activateIgnoringOtherApps:YES];
        return;
    }
    
    
    self.menubarController.hasActiveIcon = !self.menubarController.hasActiveIcon;
    self.panelController.hasActivePanel = self.menubarController.hasActiveIcon;
}

#pragma mark - Public accessors

- (PanelController *)panelController
{
    if (_panelController == nil) {
        _panelController = [[PanelController alloc] initWithDelegate:self];
        [_panelController addObserver:self forKeyPath:@"hasActivePanel" options:0 context:kContextActivePanel];
    }
    return _panelController;
}

#pragma mark - PanelControllerDelegate

- (StatusItemView *)statusItemViewForPanelController:(PanelController *)controller
{
    return self.menubarController.statusItemView;
}

@end
