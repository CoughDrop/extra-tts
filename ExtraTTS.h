// Copyright (c) 2012 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import <Cordova/CDVPlugin.h>

@interface ExtraTTS : CDVPlugin

- (void)status:(CDVInvokedUrlCommand*)command;
- (void)getAvailableVoices:(CDVInvokedUrlCommand*)command;
- (void)downloadVoice:(CDVInvokedUrlCommand*)command;
- (void)deleteVoice:(CDVInvokedUrlCommand*)command;
- (void)speakText:(CDVInvokedUrlCommand*)command;
- (void)stopSpeakingText:(CDVInvokedUrlCommand*)command;
- (BOOL)addSkipBackupAttributeToItemAtURL:(NSURL *)URL;

@end
