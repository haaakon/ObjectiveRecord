// ObjectiveRelation.m
//
// Copyright (c) 2014 Marin Usalj <http://supermar.in>
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#import "ObjectiveRelation.h"

#import "ObjectiveSugar.h"

#import "NSManagedObject+ActiveRecord.h"
#import "NSManagedObject+Mappings.h"

@interface ObjectiveRelation () <NSCopying> {
    NSArray *_fetchedObjects;
}

@property (nonatomic, copy) NSArray *where;
@property (nonatomic, copy) NSArray *order;
@property (nonatomic) NSUInteger limit;
@property (nonatomic) NSUInteger offset;

@property (nonatomic, strong) Class entity;
@property (nonatomic, strong) NSManagedObjectContext *managedObjectContext;

@end

@implementation ObjectiveRelation

+ (instancetype)relationWithEntity:(Class)entity {
    ObjectiveRelation *relation = [self new];
    relation.entity = entity;
    return relation;
}

- (id)init {
    if (self = [super init]) {
        _where = @[];
        _order = @[];
        _managedObjectContext = [NSManagedObjectContext defaultContext];
    }
    return self;
}

- (id)where:(id)condition, ... {
    va_list arguments;
    va_start(arguments, condition);
    ObjectiveRelation *relation = [self where:condition arguments:arguments];
    va_end(arguments);

    return relation;
}

- (id)where:(id)condition arguments:(va_list)arguments {
    NSPredicate *predicate = [self predicateFromObject:condition arguments:arguments];
    ObjectiveRelation *relation = [self copy];
    relation.where = [relation.where arrayByAddingObject:predicate];
    return relation;
}

- (id)order:(id)order {
    ObjectiveRelation *relation = [self copy];
    relation.order = [relation.order arrayByAddingObjectsFromArray:[self sortDescriptorsFromObject:order]];
    return relation;
}

- (id)reverseOrder {
    if ([self.order count] == 0) {
        return [self order:@{[self.entity primaryKey]: @"DESC"}];
    }

    ObjectiveRelation *relation = [self copy];
    relation.order = [relation.order valueForKey:NSStringFromSelector(@selector(reversedSortDescriptor))];
    return relation;
}

- (id)limit:(NSUInteger)limit {
    ObjectiveRelation *relation = [self copy];
    relation.limit = limit;
    return relation;
}

- (id)offset:(NSUInteger)offset {
    ObjectiveRelation *relation = [self copy];
    relation.offset = offset;
    return relation;
}

- (id)inContext:(NSManagedObjectContext *)context {
    ObjectiveRelation *relation = [self copy];
    relation.managedObjectContext = context;
    return relation;
}

- (NSUInteger)count {
    return [self.managedObjectContext countForFetchRequest:[self prepareFetchRequest] error:nil];
}

- (instancetype)all {
    return [self copy];
}

- (id)first {
    return [[self limit:1] firstObject];
}

- (id)last {
    return [[self reverseOrder] first];
}

- (id)find:(id)condition, ... {
    va_list arguments;
    va_start(arguments, condition);
    ObjectiveRelation *relation = [self where:condition arguments:arguments];
    va_end(arguments);

    return [relation first];
}

- (id)create {
    return [NSEntityDescription insertNewObjectForEntityForName:[self.entity entityName]
                                         inManagedObjectContext:self.managedObjectContext];
}

- (id)create:(NSDictionary *)attributes {
    if (attributes == nil || (id)attributes == [NSNull null]) return nil;

    NSManagedObject *newEntity = [self create];
    [newEntity update:attributes];
    return newEntity;
}

- (id)findOrCreate:(NSDictionary *)properties {
    NSDictionary *transformed = [self.entity transformProperties:properties withContext:self.managedObjectContext];

    return [[self where:transformed] first] ?: [self create:transformed];
}

- (void)deleteAll {
    for (NSManagedObject *entity in self) {
        [entity delete];
    }
}

- (NSArray *)fetchedObjects {
    if (_fetchedObjects == nil) {
        _fetchedObjects = [self.managedObjectContext executeFetchRequest:[self prepareFetchRequest] error:nil];
    }
    return _fetchedObjects;
}

#pragma mark - NSObject

- (NSString *)description {
    return [NSString stringWithFormat:@"<ObjectiveRelation where:%@ order:%@ limit:%lu offset:%lu context:%@>", self.where, self.order, (unsigned long)self.limit, (unsigned long)self.offset, self.managedObjectContext];
}

- (id)forwardingTargetForSelector:(SEL)aSelector {
    if ([NSArray instancesRespondToSelector:aSelector] && ![self respondsToSelector:aSelector]) {
        return self.fetchedObjects;
    }
    return self;
}

#pragma mark - NSCopying

- (id)copyWithZone:(NSZone *)zone
{
    ObjectiveRelation *copy = [[self class] relationWithEntity:self.entity];
    if (copy) {
        copy.where = [self.where copyWithZone:zone];
        copy.order = [self.order copyWithZone:zone];
        copy.limit = self.limit;
        copy.offset = self.offset;
        copy.managedObjectContext = self.managedObjectContext;
    }
    return copy;
}

#pragma mark - NSFastEnumeration

- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state objects:(__unsafe_unretained id [])buffer count:(NSUInteger)len {
    return [self.fetchedObjects countByEnumeratingWithState:state objects:buffer count:len];
}

#pragma mark - Private

- (NSFetchRequest *)prepareFetchRequest {
    NSFetchRequest *fetchRequest = [NSFetchRequest fetchRequestWithEntityName:[self.entity entityName]];
    [fetchRequest setEntity:[NSEntityDescription entityForName:[self.entity entityName] inManagedObjectContext:self.managedObjectContext]];
    [fetchRequest setFetchLimit:self.limit];
    [fetchRequest setFetchOffset:self.offset];
    [fetchRequest setPredicate:[NSCompoundPredicate andPredicateWithSubpredicates:self.where]];
    [fetchRequest setSortDescriptors:self.order];
    return fetchRequest;
}

- (NSPredicate *)predicateFromDictionary:(NSDictionary *)dict {
    NSArray *subpredicates = [dict map:^(id key, id value) {
        return [NSPredicate predicateWithFormat:@"%K = %@", key, value];
    }];

    return [NSCompoundPredicate andPredicateWithSubpredicates:subpredicates];
}

- (NSPredicate *)predicateFromObject:(id)condition {
    return [self predicateFromObject:condition arguments:NULL];
}

- (NSPredicate *)predicateFromObject:(id)condition arguments:(va_list)arguments {
    if ([condition isKindOfClass:[NSPredicate class]])
        return condition;

    if ([condition isKindOfClass:[NSString class]])
        return [NSPredicate predicateWithFormat:condition arguments:arguments];

    if ([condition isKindOfClass:[NSDictionary class]])
        return [self predicateFromDictionary:condition];

    return nil;
}

- (NSSortDescriptor *)sortDescriptorFromDictionary:(NSDictionary *)dict {
    BOOL isAscending = ![[dict.allValues.first uppercaseString] isEqualToString:@"DESC"];
    return [NSSortDescriptor sortDescriptorWithKey:dict.allKeys.first ascending:isAscending];
}

- (NSSortDescriptor *)sortDescriptorFromString:(NSString *)order {
    NSArray *components = [order split];

    NSString *key = [components firstObject];
    NSString *value = [components count] > 1 ? components[1] : @"ASC";

    return [self sortDescriptorFromDictionary:@{key: value}];
}

- (NSSortDescriptor *)sortDescriptorFromObject:(id)order {
    if ([order isKindOfClass:[NSSortDescriptor class]])
        return order;

    if ([order isKindOfClass:[NSString class]])
        return [self sortDescriptorFromString:order];

    if ([order isKindOfClass:[NSDictionary class]])
        return [self sortDescriptorFromDictionary:order];

    return nil;
}

- (NSArray *)sortDescriptorsFromObject:(id)order {
    if ([order isKindOfClass:[NSString class]])
        order = [order componentsSeparatedByString:@","];

    if ([order isKindOfClass:[NSArray class]])
        return [order map:^id (id object) {
            return [self sortDescriptorFromObject:object];
        }];

    return @[[self sortDescriptorFromObject:order]];
}

@end
