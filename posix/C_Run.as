// Copyright (c) 2013 Adobe Systems Inc

// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:

// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.

// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

package C_Run
{
  import flash.utils.ByteArray;
  import flash.utils.Endian;

  //CONFIG::debug { trace("CRun::loaded"); }

  /**
  * mapping of function pointer to Function
  * @private
  */
  public var ptr2fun_init:* = [];

  if(!ptr2fun_init.length)
  {
    ptr2fun_init[0] = function():void { throw new Error("null function pointer called"); };
    ptr2fun_init.length = 1;
  }
  
  /**
  * @private
  */
  public function ptr2funInit():*
  {
    // ptr2fun => "undefined" means uninitialized and type "*", so Array is right
    // ptr2fun => null means uninitialized and type Vector.<Function> so convert to Vector
    if(typeof(ptr2fun) != "undefined" && ptr2fun == null && ptr2fun_init is Array)
    {
      //trace("Converting ptr2fun_init to vector");
      var v:Vector.<Function> = new Vector.<Function>;
      v.push.apply(null, ptr2fun_init);
      ptr2fun_init.length = 0; // poison it -- no one should be holding onto it anyhow
      ptr2fun_init = v;
    }
    return ptr2fun_init;
  }

  /**
  * @private
  */
  public const domainClass:Class = (function():Class
  {
    // try to get player ApplicationDomain class
    try
    {
      var flashsystemNS:Namespace = new Namespace("flash.system");

      return flashsystemNS::["ApplicationDomain"];
    }
    catch(e:*) { }

    // try to get shell Domain class
    var avmplusNS:Namespace = new Namespace("avmplus");

    return avmplusNS::["Domain"];
  })();

  /**
  * @private
  * @see http://help.adobe.com/en_US/FlashPlatform/reference/actionscript/3/flash/concurrent/Mutex.html
  */
  public const mutexClass:Class = (function():Class
  {
    try
    {
      var flashconcNS:Namespace = new Namespace("flash.concurrent");  
            
      var mc:Class = flashconcNS::["Mutex"];      
      //AIR 3.5 for mobile exposes the Worker Class, but does not
      //provide a working implementation. This can only be detected
      //by attempting to construct one to see if it throws an
      //exception      
      var m:Object = new mc();
      m.lock();
      m.unlock();
      // If the Mutex was useable, we can safely claim to support the Mutex class
      return mc;
    }
    catch(e:*) {}

    return null;
  })();

  /**
  * @private
  */
  public const conditionClass:Class = (function():Class
  {
    try
    {
      var flashconcNS:Namespace = new Namespace("flash.concurrent");

      return flashconcNS::["Condition"];
    }
    catch(e:*) {}

    return null;
  })();

  /**
  * @private
  */
  public const workerDomainClass:Class = (function():Class
  {
    try
    {
      var flashsystemNS:Namespace = new Namespace("flash.system");

      return flashsystemNS::["WorkerDomain"];
    }
    catch(e:*) {}

    return null;
  })();

  /**
  * @private
  * We use workerClass != null as a test for existence of thread support, so make it depend on
  * other pre-reqs
  */
  public const workerClass:Class = mutexClass && conditionClass && workerDomainClass && (function():Class
  {
    try
    {
      var flashsystemNS:Namespace = new Namespace("flash.system");

      return flashsystemNS::["Worker"];
    }
    catch(e:*) { }

    return null;
  })();


  /**
  * this Worker's threadId
  * @private
  */
  public var threadId:int = workerClass ? workerClass.current.getSharedProperty("flascc.threadId") : 0;

  /**
  * this Worker's "real" (not impersonating) threadId
  * @private
  */
  public var realThreadId:int = threadId;

  /**
  * @private
  */
  public var threadArbMutex:* = workerClass ? workerClass.current.getSharedProperty("flascc.threadArbMutex") || new mutexClass : undefined;

  /**
  * @private 
  */
  public var threadArbConds:* = workerClass ? (function():* {
    var r:Array = [];
    for(var i:int = 0; i < 32; i++)
    {
      var c:* = workerClass.current.getSharedProperty("flascc.threadArbCond." + i);
      if(!c)
        return undefined;
      r[i] = c;
    }
    return r;
  })() ||
  (function():* {
    var r:Array = [];
    for(var i:int = 0; i < 32; i++)
      r[i] = new conditionClass(threadArbMutex);
    return r;
  })() :
  undefined;

  /**
  * @private 
  */
  var threadArbLockDepth:int = 0;

  /**
  * @private 
  */
  [GlobalMethod]
  public function threadArbMutexLock():void
  {
//    trace("threadArbMutexLock (" + threadId + "/" + realThreadId + ")");
    if(!threadArbLockDepth++)
      threadArbMutex.lock();
//    trace("/threadArbMutexLock (" + threadId + "/" + realThreadId + ")");
  }

  /**
  * @private 
  */
  [GlobalMethod]
  public function threadArbMutexUnlock():void
  {
//    trace("threadArbMutexUnlock (" + threadId + "/" + realThreadId + ")");
    if(!--threadArbLockDepth)
      threadArbMutex.unlock();
//    trace("/threadArbMutexUnlock (" + threadId + "/" + realThreadId + ")");
  }

  /**
  * @private 
  */
  [GlobalMethod]
  public function threadArbCondsNotify(mask:int):void
  {
//    trace("threadArbCondsNotify(" + threadId + "/" + realThreadId + ")");
    var i:int = 0;
    while(mask && i < 32)
    {
      if(mask & 1)
        threadArbConds[i].notifyAll();
      mask >>= 1;
      i++;
    }
//    trace("/threadArbCondsNotify(" + threadId + "/" + realThreadId + ")");
  }

  /**
  * @private 
  */
  [GlobalMethod]
  public function threadArbCondWait(timo:Number):Boolean
  {
//    trace("threadArbCondWait " + timo + " (" + threadId + "/" + realThreadId + ")");
    var result:Boolean;
//    try {
      result = threadArbConds[threadId & 31].wait(timo);
//    } finally {
//      trace("/threadArbCondWait " + timo + " (" + threadId + "/" + realThreadId + ")");
//    }
    return result;
  }

  /**
  * @private 
  * yuck... just for yielding!
  */
  var yieldCond:*;

  /**
  * @private 
  */
  [GlobalMethod]
  public function yield(ms:int = 1):void
  {
    if(!yieldCond)
    {
      var mutex:* = new mutexClass;
      mutex.lock();
      yieldCond = new conditionClass(mutex);
    }
    yieldCond.wait(ms);
  }

//trace("threadId: " + threadId);

  /**
  * clients who want to initialize workers on creation
  * @private
  */
  public const workerInits:Vector.<Function> = new Vector.<Function>;

  /**
  * returns a new threadId given a stack, entry function, and arguments
  * @private
  */
  [GlobalMethod]
  public function newThread(tid:int, esp_init:int, entryFun:int, args:Vector.<int>):*
  {
    CONFIG::debug { trace("CRun::newThread: " + arguments); }
    
    var w:* = createflasccWorker();

    // set up the basics
    w.setSharedProperty("flascc.threadId", tid);
    w.setSharedProperty("flascc.threadArbMutex", threadArbMutex);
    for(var i:int = 0; i < 32; i++)
      w.setSharedProperty("flascc.threadArbCond." + i, threadArbConds[i]);
    ram_init.shareable = true; // ensure shared!
    w.setSharedProperty("flascc.ram", ram_init);
    w.setSharedProperty("flascc.esp_init", esp_init);
    w.setSharedProperty("flascc.thread_entry", entryFun);

    var argsObj:ByteArray = new ByteArray;
    argsObj.writeObject(args);
    w.setSharedProperty("flascc.thread_args", argsObj);
    for each(var f:Function in workerInits)
      f(w);
    return w;
  }

  /**
  * local slot for "ram", the shared ByteArray passed via flascc.ram should:
  * - contain 0x11223344 in the [0-4]
  * - contain 0 in the [4-7] bytes
  * @private
  */
  public const ram_init:ByteArray =
    (workerClass ? workerClass.current.getSharedProperty("flascc.ram") : null) ||
    (domainClass.currentDomain.domainMemory ? domainClass.currentDomain.domainMemory : new ByteArray);

  public const RAM_MAGIC:int = 0x11223344;	
  public const ram:ByteArray = ram_init;
  public const RAM_MAGIC_POS:int = 0;
  public const RAM_LENGTH_POS:int = RAM_MAGIC_POS + 4;
  public const RAM_LENGTH_RESERVED:int = RAM_LENGTH_POS + 4;
  public const RAM_LENGTH_MIN:int = 24*1024*1024;
  public const RAM_INC_MIN:int = 1*1024*1024;
  public var isLegacy:Boolean;
  public const version:String = "v4";
  /**
   * @private
   */
  public var throwWhenOutOfMemory:Boolean = false;
  
  public function initRam():void
  {
  	trace(version + " initRam begin ");
  	ram.endian = flash.utils.Endian.LITTLE_ENDIAN;
  	if(ram.length < RAM_LENGTH_MIN)
  		ram.length = RAM_LENGTH_MIN;
  	domainClass.currentDomain.domainMemory = ram_init;  
  	if (ramGetLength() < RAM_LENGTH_RESERVED)
  		ramSetLength(RAM_LENGTH_RESERVED);
  	
  	isLegacy = ramIsLegacy();
  	trace(version + " initRam end, legacy: " + isLegacy);
  }
  
  initRam();
  
  
  public function ramIsLegacy():Boolean
  {
  	var pos:int = ram.position;
  	ram.position = RAM_MAGIC_POS;
  	var magic:int = ram.readInt();
  	ram.position = pos;
  	
  	return magic != RAM_MAGIC;
  }
  
  public function ramGetLength():int
  {
  	if (isLegacy)
  	{
  		return ram.length;
  	}
  	else {
  		var pos:int = ram.position;
  		ram.position = RAM_LENGTH_POS;
  		var length:int = ram.readInt();
  		ram.position = pos;
  		return length;
  	}
  }
  
  public function ramAtomicCompareAndSwapLength(expectedLength:int, newLength:int):int
  {
  	if (isLegacy)
  	{
  		return ram.atomicCompareAndSwapLength(expectedLength, newLength);
  	}
  	else {
  		if (newLength + RAM_LENGTH_RESERVED >= ram.length)
  			ram.length = newLength + RAM_INC_MIN;
  		var rc:int = ram.atomicCompareAndSwapIntAt(RAM_LENGTH_POS, expectedLength, newLength);
  		trace(version + " ramAtomicCompareAndSwapLength exp " + expectedLength + ", new " + newLength + ", rc " + rc + ",diff " + (newLength-expectedLength));
  		return rc;
  	}
  }
  
  public function ramSetLength(newLength:int):void
  {
  	if (isLegacy)
  	{
  		ram.length = newLength;
  	}
  	else
  	{
  		var oldLength:int = ramGetLength();
  		if (newLength + RAM_LENGTH_RESERVED> ram.length)
  			ram.length = newLength + RAM_INC_MIN;
  		var pos:int = ram.position;
  		ram.position = RAM_LENGTH_POS;
  		ram.writeInt(newLength);
  		ram.position = pos;
  		
  		trace(version + " ramSetLength old " + oldLength + ", new " + ram.length + ",diff " + (ram.length-oldLength));
  	}
  }



  /**
  * @private
  * align must be power of two!
  */
  [GlobalMethod]
  public function sbrk(size:int, align:int):int
  {
    var curLen:int = ramGetLength();
    var result:int = (curLen + align - 1) & -align;
    var newLen:int = result + size;

    if(workerClass)
    {
      for(;;)
      {
        var casLen:int;

        try {
          casLen = ramAtomicCompareAndSwapLength(curLen, newLen);
        } catch(e:*) {
          if(C_Run.throwWhenOutOfMemory) throw e;
          return -1;
        }        

        if(casLen == curLen)
          break;
        curLen = casLen;
        result = (curLen + align - 1) & -align;
        newLen = result + size;
      }
    } else {
      try {
          ramSetLength(newLen);
      } catch(e:*) {
        if(C_Run.throwWhenOutOfMemory) throw e;
        return -1;
      }
    }
    return result;
  }

  /**
  * @private
  */
  public const stackSize:int = 1024 * 1024; // keep in sync w/ THR_STACK_DEFAULT

  /**
  * @private
  */
  public const stackAlign:int = 16; // keep in sync w/ ISelLowering

  /**
  * @private
  */
  public const pageSize:int = 4096;

  /**
  * @private
  */
  public var ESP_init:int = (workerClass ? workerClass.current.getSharedProperty("flascc.esp_init") : 0) || 
    // stackSize * 2 for initial thread! (keep in sync w/ THR_STACK_INITIAL)
    ((stackSize * 2) + sbrk(stackSize * 2, pageSize));

  /**
  * @private
  */
  public const inf:Number = Number.POSITIVE_INFINITY;
  /**
  * @private 
  */
  public const nan:Number = Number.NaN;

  /**
  * @private
  */
  [Weak] public var ESP:int;
 
  /**
  * @private
  */
  [Weak] public var eax:int;
 
  /**
  * @private
  */
  [Weak] public var edx:int;
 
  /**
  * @private
  */
  [Weak] public var st0:Number;
}
