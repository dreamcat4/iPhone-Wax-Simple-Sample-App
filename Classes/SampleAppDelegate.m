//
//  SampleAppDelegate.m
//  Sample
//
//  Created by Dan Grigsby on 9/30/09.
//  Copyright __MyCompanyName__ 2009. All rights reserved.

#import "SampleAppDelegate.h"

#import "ProtocolLoader.h"
#import "WaxTextField.h"

#import "wax.h"

@implementation SampleAppDelegate

@synthesize window;

- (void)dealloc {
    [window release];
    [super dealloc];
}

- (void)applicationDidFinishLaunching:(UIApplication *)application {    
    [window makeKeyAndVisible];
    
    wax_start();
    
    // If you want to load wax with some extensions use this function
    //wax_startWithExtensions(luaopen_HTTPotluck, luaopen_json, nil);
}


@end
