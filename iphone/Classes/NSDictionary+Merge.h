//
//  NSDictionary+Merge.h
//  Titanium
//
//  Created by Martin Guillon on 06/02/14.
//
//

#import <Foundation/Foundation.h>

@interface NSDictionary (Merge)

+ (NSDictionary *) dictionaryByMerging: (NSDictionary *) dict1 with: (NSDictionary *) dict2;
- (NSDictionary *) dictionaryByMergingWith: (NSDictionary *) dict;

@end
