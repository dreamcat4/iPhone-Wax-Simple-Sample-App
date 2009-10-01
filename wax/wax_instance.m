/*
 *  wax_instance.c
 *  Lua
 *
 *  Created by ProbablyInteractive on 5/18/09.
 *  Copyright 2009 Probably Interactive. All rights reserved.
 *
 */

#import "wax_instance.h"
#import "wax.h"
#import "wax_helpers.h"

#import "lauxlib.h"
#import "lobject.h"

static const struct luaL_Reg metaFunctions[] = {
    {"__index", __index},
    {"__newindex", __newindex},
    {"__gc", __gc},
    {"__waxretain", __waxretain},
    {"__tostring", __tostring},
    {"__eq", __eq},
    {NULL, NULL}
};

static const struct luaL_Reg functions[] = {
    {"methods", methods},
    {NULL, NULL}
};

int luaopen_wax_instance(lua_State *L) {
    BEGIN_STACK_MODIFY(L);
    
    luaL_newmetatable(L, WAX_INSTANCE_METATABLE_NAME);
    luaL_register(L, NULL, metaFunctions);
    luaL_register(L, WAX_INSTANCE_METATABLE_NAME, functions);    
    
    END_STACK_MODIFY(L, 0)
    
    return 1;
}

#pragma mark Instance Utils
#pragma -------------------

// Creates userdata object for obj-c instance/class and pushes it onto the stack
wax_instance_userdata *wax_instance_create(lua_State *L, id instance, BOOL isClass) {
    BEGIN_STACK_MODIFY(L)
    
    // Does user data already exist?
    wax_instance_pushUserdata(L, instance);
   
    if (lua_isnil(L, -1)) {
        wax_log(LOG_GC, @"Creating object for %@(%p)", instance, instance);
        lua_pop(L, 1); // pop nil stack
    }
    else {
        wax_log(LOG_GC, @"Found existing userdata object for %@(%p)", instance, instance);
        return lua_touserdata(L, -1);
    }
    
    size_t nbytes = sizeof(wax_instance_userdata);
    wax_instance_userdata *instanceUserdata = (wax_instance_userdata *)lua_newuserdata(L, nbytes);
    instanceUserdata->instance = instance;
    instanceUserdata->isClass = isClass;
    instanceUserdata->isSuper = NO;
 
    if (!isClass) {
        wax_log(LOG_GC, @"Retaining object for %@(%p)", instance, instance);        
        [instanceUserdata->instance retain];
    }
    
    // set the metatable
    luaL_getmetatable(L, WAX_INSTANCE_METATABLE_NAME);
    lua_setmetatable(L, -2);

    // give it a nice clean environment
    // TODO: Is this step needed?
    lua_newtable(L); 
    lua_setfenv(L, -2);
    
    // look for weak table
    luaL_getmetatable(L, WAX_INSTANCE_METATABLE_NAME);
    lua_getfield(L, -1, "__wax_userdata");
    
    if (lua_isnil(L, -1)) { // Create new weak table, add it to metatable
        lua_pop(L, 1); // Remove nil
        
        lua_newtable(L);
        lua_pushvalue(L, -1);
        lua_setmetatable(L, -1); // "wax_userdata" is it's own metatable
        
        lua_pushstring(L, "v!");
        lua_setfield(L, -2, "__mode");  // Make weak table
                
        lua_pushstring(L, "__wax_userdata"); // Table name
        lua_pushvalue(L, -2); // copy the userdata table
        lua_rawset(L, -4); // Add __wax_userdata table to metatable      
    }

    
    // register the userdata in the weak table in the metatable (so we can access it from obj-c)
    lua_pushlightuserdata(L, instanceUserdata->instance);
    lua_pushvalue(L, -4); // Push userdata
    lua_rawset(L, -3);
        
    lua_pop(L, 2); // Pop off userdata table and metatable
    
    END_STACK_MODIFY(L, 1)
    
    return instanceUserdata;
}

// Creates pseudo-super userdata object for obj-c instance and pushes it onto the stack
wax_instance_userdata *wax_instance_createSuper(lua_State *L, wax_instance_userdata *instanceUserdata) {
    BEGIN_STACK_MODIFY(L)
    
    size_t nbytes = sizeof(wax_instance_userdata);
    wax_instance_userdata *superInstanceUserdata = (wax_instance_userdata *)lua_newuserdata(L, nbytes);
    superInstanceUserdata->instance = instanceUserdata->instance;
    superInstanceUserdata->isClass = instanceUserdata->isClass;
    superInstanceUserdata->isSuper = YES;
    
    // set the metatable
    luaL_getmetatable(L, WAX_INSTANCE_METATABLE_NAME);
    lua_setmetatable(L, -2);
        
    END_STACK_MODIFY(L, 1)
    
    return superInstanceUserdata;
}

// First look in the object's userdata for the function, then look in the object's class's userdata
BOOL wax_instance_pushFunction(lua_State *L, id self, SEL selector) {
    BEGIN_STACK_MODIFY(L)
    
    wax_instance_pushUserdata(L, self);
    if (lua_isnil(L, -1)) {
        END_STACK_MODIFY(L, 0)
        return NO; // userdata doesn't exist
    }
    
    lua_getfenv(L, -1);
    wax_pushMethodNameFromSelector(L, selector);
    lua_rawget(L, -2);
    
    BOOL result = YES;
    
    if (!lua_isfunction(L, -1)) { // function not found in userdata
        if ([self class] == self) result = NO; // End of the line bub, can't go any further up
        else result = wax_instance_pushFunction(L, [self class], selector);
    }
    
    END_STACK_MODIFY(L, 1)
    
    return result;
}

void wax_instance_pushUserdata(lua_State *L, id object) {
    BEGIN_STACK_MODIFY(L);
    
    luaL_getmetatable(L, WAX_INSTANCE_METATABLE_NAME);
    lua_getfield(L, -1, "__wax_userdata");
    
    if (lua_isnil(L, -1)) { // __wax_userdata table does not exist yet 
        lua_remove(L, -2); // remove metadata table
    }
    else {
        lua_pushlightuserdata(L, object);    
        lua_rawget(L, -2);
        lua_remove(L, -2); // remove __wax_userdata table
        lua_remove(L, -2); // remove metadata table
    }
    
    END_STACK_MODIFY(L, 1)
}

#pragma mark Override Metatable Functions
#pragma ---------------------------------

static int __index(lua_State *L) {
    wax_instance_userdata *instanceUserdata = (wax_instance_userdata *)luaL_checkudata(L, 1, WAX_INSTANCE_METATABLE_NAME);    
    
    if (lua_isstring(L, 2) && strcmp("super", lua_tostring(L, 2)) == 0) { // call to super!        
        wax_instance_createSuper(L, instanceUserdata);        
        return 1;
    }
    
    // Check instance userdata
    lua_getfenv(L, -2);
    lua_pushvalue(L, -2);
    lua_rawget(L, 3);

    // Check instance's class userdata
    if (lua_isnil(L, -1) && !instanceUserdata->isClass && !instanceUserdata->isSuper) {
        lua_pop(L, 1);
        
        wax_instance_pushUserdata(L, [instanceUserdata->instance class]);
        
        // If there is no userdata for this instance's class, then leave the nil on the stack and don't anything else
        if (!lua_isnil(L, -1)) {
            lua_getfenv(L, -1);
            lua_pushvalue(L, 2);
            lua_rawget(L, -2);
            lua_remove(L, -2); // Get rid of the userdata env
            lua_remove(L, -2); // Get rid of the userdata
        }        
    }
            
    if (instanceUserdata->isSuper || lua_isnil(L, -1) ) { // Couldn't find that in the userdata environment table, assume it is defined in obj-c classes
        SEL selector = wax_selectorForInstance(instanceUserdata, lua_tostring(L, 2), NO);

        if (selector) { // If the class has a method with this name, push as a closure            
            lua_pushstring(L, sel_getName(selector));
            lua_pushcclosure(L, instanceUserdata->isSuper ? superMethodClosure : methodClosure, 1);
        }
    }
    else if (instanceUserdata->isClass && wax_isInitMethod(lua_tostring(L, 2))) { // Is this an init method create in lua?
        lua_pushcclosure(L, customInitMethodClosure, 1);
    }
    
    return 1;
}

static int __newindex(lua_State *L) {
    wax_instance_userdata *instanceUserdata = (wax_instance_userdata *)luaL_checkudata(L, 1, WAX_INSTANCE_METATABLE_NAME);
    
    // If this already exists in a protocol, or superclass make sure it will call the lua functions
    if (lua_type(L, 3) == LUA_TFUNCTION) {
        overrideMethod(L, instanceUserdata);
    }
    
    // Add value to the userdata's environment table
    lua_getfenv(L, 1);
    lua_insert(L, 2);
    lua_rawset(L, 2);        
    
    return 0;
}

static int __waxretain(lua_State *L) {
  wax_instance_userdata *instanceUserdata = (wax_instance_userdata *)luaL_checkudata(L, 1, WAX_INSTANCE_METATABLE_NAME);

  if (!instanceUserdata->isClass && !instanceUserdata->isSuper && [instanceUserdata->instance retainCount] > 1) {
    lua_pushboolean(L, true);
  }
  else {
    lua_pushboolean(L, false);
  }
  
  return 1;
}


static int __gc(lua_State *L) {
    wax_instance_userdata *instanceUserdata = (wax_instance_userdata *)luaL_checkudata(L, 1, WAX_INSTANCE_METATABLE_NAME);
    if (!instanceUserdata->isClass && !instanceUserdata->isSuper) {
        wax_log(LOG_GC, @"Releasing %@(%p)", [instanceUserdata->instance class], instanceUserdata->instance);
        [instanceUserdata->instance release];
    }
    
    return 0;
}

static int __tostring(lua_State *L) {
    wax_instance_userdata *instanceUserdata = (wax_instance_userdata *)luaL_checkudata(L, 1, WAX_INSTANCE_METATABLE_NAME);
    lua_pushstring(L, [[NSString stringWithFormat:@"(%p => %p) %@", instanceUserdata, instanceUserdata->instance, instanceUserdata->instance] UTF8String]);
    
    return 1;
}

static int __eq(lua_State *L) {
    wax_instance_userdata *o1 = (wax_instance_userdata *)luaL_checkudata(L, 1, WAX_INSTANCE_METATABLE_NAME);
    wax_instance_userdata *o2 = (wax_instance_userdata *)luaL_checkudata(L, 2, WAX_INSTANCE_METATABLE_NAME);
    
    lua_pushboolean(L, [o1->instance isEqual:o2->instance]);
    return 1;
}

#pragma mark Userdata Functions
#pragma -----------------------

static int methods(lua_State *L) {
    wax_instance_userdata *instanceUserdata = (wax_instance_userdata *)luaL_checkudata(L, 1, WAX_INSTANCE_METATABLE_NAME);
    
    uint count;
    Method *methods = class_copyMethodList([instanceUserdata->instance class], &count);
    
    lua_newtable(L);
    
    for (int i = 0; i < count; i++) {
        Method method = methods[i];
        lua_pushstring(L, sel_getName(method_getName(method)));
        lua_rawseti(L, -2, i + 1);
    }

    return 1;
}

#pragma mark Function Closures
#pragma ----------------------

static int methodClosure(lua_State *L) {
    if (![[NSThread currentThread] isEqual:[NSThread mainThread]]) NSLog(@"METHODCLOSURE: OH NO SEPERATE THREAD");
    
    wax_instance_userdata *instanceUserdata = (wax_instance_userdata *)luaL_checkudata(L, 1, WAX_INSTANCE_METATABLE_NAME);    
    const char *selectorName = luaL_checkstring(L, lua_upvalueindex(1));
    SEL selector = sel_getUid(selectorName);
    BOOL autoAlloc = NO;
        
    if (instanceUserdata->isClass && wax_isInitMethod(selectorName)) {
        // If init is called on a class, allocate it.
        // This is done to get around the placeholder stuff the foundation class uses
        instanceUserdata = wax_instance_create(L, [instanceUserdata->instance alloc], NO);
        autoAlloc = YES;
        
        // Also, replace the old userdata with the new one!
        lua_replace(L, 1);
    }
    
    NSMethodSignature *signature = [instanceUserdata->instance methodSignatureForSelector:selector];
    if (!signature) {
        const char *className = [NSStringFromClass([instanceUserdata->instance class]) UTF8String];
        luaL_error(L, "'%s' has no method selector '%s'", className, selectorName);
    }
    
    NSInvocation *invocation = nil;
    invocation = [NSInvocation invocationWithMethodSignature:signature];
        
    [invocation setTarget:instanceUserdata->instance];
    [invocation setSelector:selector];
    
    int objcArgumentCount = [signature numberOfArguments] - 2; // skip the hidden self and _cmd argument
    
    void **arguements = calloc(sizeof(void*), objcArgumentCount);
    for (int i = 0; i < objcArgumentCount; i++) {
        arguements[i] = wax_copyToObjc(L, [signature getArgumentTypeAtIndex:i + 2], i + 2, nil);
        [invocation setArgument:arguements[i] atIndex:i + 2];
    }

    @try {
        [invocation invoke];
    }
    @catch (NSException *exception) {
        luaL_error(L, "Error invoking method '%s' on '%s' because %s", selector, class_getName([instanceUserdata->instance class]), [[exception description] UTF8String]);
    }
    
    // Free the arguements
    for (int i = 0; i < objcArgumentCount; i++) {
        free(arguements[i]);
    }
    free(arguements);
    
    int methodReturnLength = [signature methodReturnLength];
    if (methodReturnLength > 0) {
        // TODO use lua buffers for strings
        void *buffer = calloc(1, methodReturnLength);
        [invocation getReturnValue:buffer];
            
        wax_fromObjc(L, [signature methodReturnType], buffer);
                
        if (lua_isuserdata(L, -1) && (
            autoAlloc || // If autoAlloc'd then we assume the returned object is the same as the alloc'd method (gets around placeholder problem)
            strcmp(selectorName, "alloc") == 0 || // If this object was alloc, retain, copy then don't "auto retain"
            strcmp(selectorName, "copy") == 0 || 
            strcmp(selectorName, "mutableCopy") == 0 ||
            strcmp(selectorName, "allocWithZone") == 0 ||
            strcmp(selectorName, "copyWithZone") == 0 ||
            strcmp(selectorName, "mutableCopyWithZone") == 0)) {
            // strcmp(selectorName, "retain") == 0 || // explicit retaining should not autorelease
            
            wax_instance_userdata *returnedObjLuaInstance = (wax_instance_userdata *)lua_topointer(L, -1);
            wax_log(LOG_GC, @"Releasing %@(%p) autoAlloc=%d", [returnedObjLuaInstance->instance class], instanceUserdata->instance, autoAlloc);            
            [returnedObjLuaInstance->instance release];
        }
        else if (autoAlloc && lua_isnil(L, -1)) {
          // The init method returned nil... means initializization failed! Zero out the userdata
          instanceUserdata->instance = nil;
        }
        
        free(buffer);
    }
    
    return 1;
}

static int superMethodClosure(lua_State *L) {
    wax_instance_userdata *instanceUserdata = (wax_instance_userdata *)luaL_checkudata(L, 1, WAX_INSTANCE_METATABLE_NAME);
    const char *selectorName = luaL_checkstring(L, lua_upvalueindex(1));    
    SEL selector = sel_getUid(selectorName);
    
    // Super Swizzle
    id instance = instanceUserdata->instance;

    Method selfMethod = class_getInstanceMethod([instance class], selector);
    Method superMethod = class_getInstanceMethod([instance superclass], selector);        
    
    if (superMethod && selfMethod != superMethod) { // Super's got what you're looking for
        IMP selfMethodImp = method_getImplementation(selfMethod);        
        IMP superMethodImp = method_getImplementation(superMethod);
        method_setImplementation(selfMethod, superMethodImp);
        
        methodClosure(L);
        
        method_setImplementation(selfMethod, selfMethodImp); // Swap back to self's original method
    }
    else {
        methodClosure(L);
    }
    
    
    return 1;
}

static int customInitMethodClosure(lua_State *L) {
    wax_instance_userdata *instanceUserdata = (wax_instance_userdata *)luaL_checkudata(L, 1, WAX_INSTANCE_METATABLE_NAME);
    
    if (instanceUserdata->isClass) {
        instanceUserdata = wax_instance_create(L, [instanceUserdata->instance alloc], NO);
        [instanceUserdata->instance release]; // The userdata is taking care of retaining this now
        lua_replace(L, 1); // replace the old userdata with the new one!
    }
    else {
        luaL_error(L, "I WAS TOLD THIS WAS A CUSTOM INIT METHOD. BUT YOU LIED TO ME");
    }
    
    lua_pushvalue(L, lua_upvalueindex(1)); // Grab the function!
    lua_insert(L, 1); // push it up top
    
    if (wax_pcall(L, lua_gettop(L) - 1, 1)) {
        const char* errorString = lua_tostring(L, -1);
        luaL_error(L, "Custom init method on '%s' failed.\n%s", class_getName([instanceUserdata->instance class]), errorString);
    }
    
    // Possibly check to make sure the custom init returns a userdata object or nil
  
    if (lua_isnil(L, -1)) {
        // The init method returned nil... means initializization failed! Zero out the userdata
        instanceUserdata->instance = nil;
    }
  
    return 1;
}

#pragma mark Override Methods
#pragma ---------------------

static int pcallUserdata(lua_State *L, id self, SEL selector, va_list args) {
    BEGIN_STACK_MODIFY(L)    
    
    if (![[NSThread currentThread] isEqual:[NSThread mainThread]]) NSLog(@"PACALLUSERDATA: OH NO SEPERATE THREAD");
    
    // Find the function... could be in the object or in the class
    if (!wax_instance_pushFunction(L, self, selector)) goto error; // function not found in userdata...
    
    // Push userdata as the first argument
    wax_fromInstance(L, self);
    if (lua_isnil(L, -1)) {
        lua_pushfstring(L, "Could not convert '%s' into lua", class_getName([self class]));
        goto error;
    }
                
    NSMethodSignature *signature = [self methodSignatureForSelector:selector];
    int nargs = [signature numberOfArguments] - 1; // Don't send in the _cmd argument, only self
    int nresults = [signature methodReturnLength] ? 1 : 0;
        
    for (int i = 2; i < [signature numberOfArguments]; i++) { // start at 2 because to skip the automatic self and _cmd arugments
        const char *type = [signature getArgumentTypeAtIndex:i];
        int size = wax_fromObjc(L, type, args);
        args += size; // HACK! Since va_arg requires static type, I manually increment the args
    }

    if (wax_pcall(L, nargs, nresults)) { // Userdata will allways be the first object sent to the function  
        goto error;
    }
    
    END_STACK_MODIFY(L, nresults)
    return nresults;
    
error:
    END_STACK_MODIFY(L, 1)
    return -1;
}

#define WAX_METHOD_NAME(_type_) wax_##_type_##_call

#define WAX_METHOD(_type_) \
static _type_ WAX_METHOD_NAME(_type_)(id self, SEL _cmd, ...) { \
va_list args; \
va_start(args, _cmd); \
va_list args_copy; \
va_copy(args_copy, args); \
/* Grab the static L... this is a hack */ \
lua_State *L = wax_currentLuaState(); \
BEGIN_STACK_MODIFY(L); \
int result = pcallUserdata(L, self, _cmd, args_copy); \
va_end(args_copy); \
va_end(args); \
if (result == -1) { \
    luaL_error(L, "Error calling '%s' on lua object '%s'\n%s", _cmd, [[self description] UTF8String], lua_tostring(L, -1)); \
} \
else if (result == 0) { \
    _type_ returnValue; \
    bzero(&returnValue, sizeof(_type_)); \
    END_STACK_MODIFY(L, 0) \
    return returnValue; \
} \
\
NSMethodSignature *signature = [self methodSignatureForSelector:_cmd]; \
_type_ *pReturnValue = (_type_ *)wax_copyToObjc(L, [signature methodReturnType], -1, nil); \
_type_ returnValue = *pReturnValue; \
free(pReturnValue); \
END_STACK_MODIFY(L, 0) \
return returnValue; \
}

typedef struct _buffer_16 {char b[16];} buffer_16;

WAX_METHOD(buffer_16)
WAX_METHOD(id)
WAX_METHOD(int)
WAX_METHOD(long)
WAX_METHOD(float)
WAX_METHOD(BOOL) 

// Only allow classes to do this
static BOOL overrideMethod(lua_State *L, wax_instance_userdata *instanceUserdata) {
    BEGIN_STACK_MODIFY(L);
    BOOL success = NO;
    const char *methodName = lua_tostring(L, 2);
    SEL selector = wax_selectorForInstance(instanceUserdata, methodName, YES);
    Class class = [instanceUserdata->instance class];
    
    const char *typeDescription = nil;
    char *returnType = nil;
    
    Method method = class_getInstanceMethod(class, selector);
        
    if (method) { // Is method defined in the superclass?
        typeDescription = method_getTypeEncoding(method);        
        returnType = method_copyReturnType(method);
    }
    else { // Does this object implement a protocol with this method?
        uint count;
        Protocol **protocols = class_copyProtocolList(class, &count);
        
        SEL *posibleSelectors = &wax_selectorsForName(methodName).selectors[0];
        
        for (int i = 0; !returnType && i < count; i++) {
            Protocol *protocol = protocols[i];
            struct objc_method_description m_description;
            
            for (int j = 0; !returnType && j < 2; j++) {
                selector = posibleSelectors[j];
                
                m_description = protocol_getMethodDescription(protocol, selector, YES, YES);
                if (!m_description.name) m_description = protocol_getMethodDescription(protocol, selector, NO, YES); // Check if it is not a "required" method
                
                if (m_description.name) {
                    typeDescription = m_description.types;
                    returnType = method_copyReturnType((Method)&m_description);
                }
            }
        }
        
        free(protocols);
    }
    
    if (returnType) { // Matching method found! Create an Obj-C method on the 
        if (!instanceUserdata->isClass) {
            luaL_error(L, "Trying to override method '%s' on an instance. You can only override classes", methodName);
        }            
        
        const char *simplifiedReturnType = wax_removeProtocolEncodings(returnType);
        IMP imp;
        switch (simplifiedReturnType[0]) {
            case WAX_TYPE_VOID:
            case WAX_TYPE_ID:
                imp = (IMP)WAX_METHOD_NAME(id);
                break;
                
            case WAX_TYPE_CHAR:
            case WAX_TYPE_INT:
            case WAX_TYPE_SHORT:
            case WAX_TYPE_UNSIGNED_CHAR:
            case WAX_TYPE_UNSIGNED_INT:
            case WAX_TYPE_UNSIGNED_SHORT:   
                imp = (IMP)WAX_METHOD_NAME(int);
                break;            
                
            case WAX_TYPE_LONG:
            case WAX_TYPE_LONG_LONG:
            case WAX_TYPE_UNSIGNED_LONG:
            case WAX_TYPE_UNSIGNED_LONG_LONG:
                imp = (IMP)WAX_METHOD_NAME(long);
                
            case WAX_TYPE_FLOAT:
                imp = (IMP)WAX_METHOD_NAME(float);
                break;
                
            case WAX_TYPE_C99_BOOL:
                imp = (IMP)WAX_METHOD_NAME(BOOL);
                break;
                
            case WAX_TYPE_STRUCT: {
                int size = wax_sizeOfTypeDescription(simplifiedReturnType);
                switch (size) {
                    case 16:
                        imp = (IMP)WAX_METHOD_NAME(buffer_16);
                        break;
                    default:
                        luaL_error(L, "Trying to override a method that has a struct return type of size '%d'. There is no implementation for this size yet.", size);
                        break;
                }
                break;
            }
                
            default:   
                luaL_error(L, "Can't override method with return type %s", simplifiedReturnType);
                break;
        }
        
        success = class_addMethod(class, selector, imp, typeDescription);
        free(returnType);                
    }
    else {
        //NSLog(@"No method name '%s' found in superclass or protocols", methodName);
    }
    
    END_STACK_MODIFY(L, 1)
    return success;
}