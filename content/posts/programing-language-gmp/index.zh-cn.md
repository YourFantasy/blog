---
title: "GMP调度模型"
subtitle: ""
date: 2023-09-17T08:59:43+08:00
lastmod: 2023-09-17T08:59:43+08:00
draft: false
author: "Bard"
authorLink: "www.bardblog.cn"
description: "详解golang 的gmp调度模型"
license: ""
images: []

tags: ["Go","GMP","Gorotinue","Thread"]
categories: ["technology"]

featuredImage: ""
featuredImagePreview: ""
twemoji: true
lightgallery: true
ruby: true
fraction: true
fontawesome: true
linkToMarkdown: true
rssFullText: false

toc:
  enable: true
  auto: true
code:
  copy: true
  maxShownLines: 50
math:
  enable: false
  # ...
mapbox:
  # ...
share:
  enable: true
  # ...
comment:
  enable: true
  # ...
---

<!--more-->
## 进程线程协程
无论程序是用什么编程语言编写的，最终它都会在操作系统中运行。一个运行中的程序可以被视为一个进程，每个进程都有自己的内存空间和资源，且进程之间是相互隔离的。通常情况下，一个应用程序的功能并非单一，例如一个聊天应用，在进行语音通话的同时还可以进行文字聊天。那么，究竟是什么支撑着这些功能的运行呢？显然不是进程。这就引出了另一个概念：线程。线程是属于某个进程的，一个进程可以拥有多个线程，这些线程并发执行以支持进程的多个功能。进程和线程都是操作系统的基本单位或资源，多线程技术可以充分利用现代CPU的多核资源，以更高效地完成进程的多个任务。

进程-线程两级结构是当今大多数软件所采用的模式。然而，线程并非足够轻量。我们使用线程是为了让它完成某个具体任务，但线程除了完成任务本身所需的时间外，还有一些额外的开销，如线程切换。当线程因I/O或锁等原因阻塞时，就会发生线程切换。但这个切换过程并不是足够快，很多时候切换的耗时高于执行任务的耗时，导致CPU资源得不到充分利用。因此，我们需要一个更轻量级的执行单元，使得切换过程更加高效，从而充分利用CPU资源。拿go语言来说，Go语言通过实现协程（goroutine）和一套调度机制，为开发者提供了更轻量级的执行单元。协程相较于线程，需要保存的上下文内容更少，切换速度更快，因此能够充分高效地利用系统资源，提高系统并发度。

协程是用户级线程，它们由Go运行时（runtime）进行管理和调度，而非直接由操作系统管理。这使得Go运行时可以在较少的操作系统线程上调度大量的协程，降低了线程切换的开销。当一个协程因I/O或其他原因阻塞时，Go运行时会将其他协程调度到同一个操作系统线程上运行，从而实现高效的并发执行。

Go语言的协程模型使得编写高并发程序变得更加简单。通过使用关键字`go`，开发者可以轻松地创建一个新的协程并发执行函数。Go语言还提供了强大的并发原语，如通道（channel）和同步原语（如互斥锁和WaitGroup），以帮助开发者在协程之间进行安全的数据传递和同步。

Go语言通过实现协程和一套调度机制，为开发者提供了一种更轻量级、高效的并发编程模型，使得充分利用CPU资源和提高系统并发度成为可能。
## GMP调度机制
Go语言实现了一套高效的调度机制，在运行时管理和调度goroutine，而不是让操作系统直接管理。这种机制类似于“虚拟线程”的概念，Go在语言层面模拟了操作系统线程切换机制。

在传统的进程-线程二级结构中，一个线程隶属于某个固定的进程，一个进程可以拥有多个线程，形成1:M的模型。然而，在Go语言的GMP模型中，协程（G）和线程（M）之间形成了一个M:N的模型。这意味着一个协程并不是固定承载在一个线程上，而是可以在多个线程之间切换和轮转执行。这种模型允许更加高效地利用系统资源，提高并发性能。

GMP模型中的三个主要组件分别是：G（goroutine，协程）、M（machine，线程）和P（processor，处理器，不是指的cpu）。G表示协程，M表示操作系统线程，P表示Go运行时的调度器。在这个模型中，P负责将G调度到M上执行。一个P可以管理多个G，一个M可以关联到一个P。这种M:N的关系使得Go运行时可以在较少的操作系统线程上调度大量的协程，降低了线程切换的开销。
![GMP](gmp.png "GMP调度机制")
### G
G就是我们常说的goroutinue，G的本体是个结构体，保存着协程的上下文、状态、协程栈等信息，对应着`src/runtime/runtime2.go:414`的g结构体
```go
type g struct {
	// Stack parameters.
	// stack describes the actual stack memory: [stack.lo, stack.hi).
	// stackguard0 is the stack pointer compared in the Go stack growth prologue.
	// It is stack.lo+StackGuard normally, but can be StackPreempt to trigger a preemption.
	// stackguard1 is the stack pointer compared in the C stack growth prologue.
	// It is stack.lo+StackGuard on g0 and gsignal stacks.
	// It is ~0 on other goroutine stacks, to trigger a call to morestackc (and crash).
	stack       stack   // offset known to runtime/cgo
	stackguard0 uintptr // offset known to liblink
	stackguard1 uintptr // offset known to liblink

	_panic    *_panic // innermost panic - offset known to liblink
	_defer    *_defer // innermost defer
	m         *m      // current m; offset known to arm liblink
	sched     gobuf
	syscallsp uintptr // if status==Gsyscall, syscallsp = sched.sp to use during gc
	syscallpc uintptr // if status==Gsyscall, syscallpc = sched.pc to use during gc
	stktopsp  uintptr // expected sp at top of stack, to check in traceback
	// param is a generic pointer parameter field used to pass
	// values in particular contexts where other storage for the
	// parameter would be difficult to find. It is currently used
	// in three ways:
	// 1. When a channel operation wakes up a blocked goroutine, it sets param to
	//    point to the sudog of the completed blocking operation.
	// 2. By gcAssistAlloc1 to signal back to its caller that the goroutine completed
	//    the GC cycle. It is unsafe to do so in any other way, because the goroutine's
	//    stack may have moved in the meantime.
	// 3. By debugCallWrap to pass parameters to a new goroutine because allocating a
	//    closure in the runtime is forbidden.
	param        unsafe.Pointer
	atomicstatus atomic.Uint32
	stackLock    uint32 // sigprof/scang lock; TODO: fold in to atomicstatus
	goid         uint64
	schedlink    guintptr
	waitsince    int64      // approx time when the g become blocked
	waitreason   waitReason // if status==Gwaiting

	preempt       bool // preemption signal, duplicates stackguard0 = stackpreempt
	preemptStop   bool // transition to _Gpreempted on preemption; otherwise, just deschedule
	preemptShrink bool // shrink stack at synchronous safe point

	// asyncSafePoint is set if g is stopped at an asynchronous
	// safe point. This means there are frames on the stack
	// without precise pointer information.
	asyncSafePoint bool

	paniconfault bool // panic (instead of crash) on unexpected fault address
	gcscandone   bool // g has scanned stack; protected by _Gscan bit in status
	throwsplit   bool // must not split stack
	// activeStackChans indicates that there are unlocked channels
	// pointing into this goroutine's stack. If true, stack
	// copying needs to acquire channel locks to protect these
	// areas of the stack.
	activeStackChans bool
	// parkingOnChan indicates that the goroutine is about to
	// park on a chansend or chanrecv. Used to signal an unsafe point
	// for stack shrinking.
	parkingOnChan atomic.Bool

	raceignore    int8  // ignore race detection events
	tracking      bool  // whether we're tracking this G for sched latency statistics
	trackingSeq   uint8 // used to decide whether to track this G
	trackingStamp int64 // timestamp of when the G last started being tracked
	runnableTime  int64 // the amount of time spent runnable, cleared when running, only used when tracking
	lockedm       muintptr
	sig           uint32
	writebuf      []byte
	sigcode0      uintptr
	sigcode1      uintptr
	sigpc         uintptr
	parentGoid    uint64          // goid of goroutine that created this goroutine
	gopc          uintptr         // pc of go statement that created this goroutine
	ancestors     *[]ancestorInfo // ancestor information goroutine(s) that created this goroutine (only used if debug.tracebackancestors)
	startpc       uintptr         // pc of goroutine function
	racectx       uintptr
	waiting       *sudog         // sudog structures this g is waiting on (that have a valid elem ptr); in lock order
	cgoCtxt       []uintptr      // cgo traceback context
	labels        unsafe.Pointer // profiler labels
	timer         *timer         // cached timer for time.Sleep
	selectDone    atomic.Uint32  // are we participating in a select and did someone win the race?

	// goroutineProfiled indicates the status of this goroutine's stack for the
	// current in-progress goroutine profile
	goroutineProfiled goroutineProfileStateHolder

	// Per-G tracer state.
	trace gTraceState

	// Per-G GC state

	// gcAssistBytes is this G's GC assist credit in terms of
	// bytes allocated. If this is positive, then the G has credit
	// to allocate gcAssistBytes bytes without assisting. If this
	// is negative, then the G must correct this by performing
	// scan work. We track this in bytes to make it fast to update
	// and check for debt in the malloc hot path. The assist ratio
	// determines how this corresponds to scan work debt.
	gcAssistBytes int64
}
```
可以将G（goroutine）理解为一个变量，它保存了当前协程的相关信息，包括栈信息、状态信息、defer、panic以及当前挂靠的线程信息等。协程可以粗略地看作一段正在运行或将要运行的函数。实际上，代码逻辑并不能直接在G上运行，而是由线程从队列中取出G并执行。G可以看作一个任务（task），保存着代码运行的上下文。

这个任务很多时候不是一次性执行完的，而是被多个线程接力执行多次，才能完成。换句话说，协程切换的频率相比于线程要高得多。但是由于协程占用的资源更少，切换过程也更迅速，因此在上下文切换上耗费的时间比例更低。这使得用于执行任务的时间更多，从而提高了CPU的有效利用率。

### M
M（machine）对应于操作系统的一个线程，负责从队列中取出一个G（goroutine）进行执行。在同一时刻，一个M只能运行一个G。与传统模式不同，上下文切换由G完成而非M。M作为真正执行代码的实体，在执行完G的全部或部分任务后，会更新G的状态，并将其重新放入工作队列中，然后继续取出其他G执行。

假设我的机器是4核，我没有做额外的设置，M的数量就是4，在go程序进程启动的时候，会调用操作系统的APi创建4个线程分配给进程的runtime，这四个线程在程序运行过程中会被重复利用，而不会被回收，即使当前Go程序最多只有3个协程。这种机制有助于减少线程创建和销毁的开销，提高系统的并发性能。
假设四个线程的ID分别是1001、1002、1003和1004，它们在程序运行过程中是固定的。如果Go程序进程有50万个协程，协程切换非常迅速，那么这四个线程就像一个“永动机”，不停地执行这50万个G（goroutine）。

相比于传统的进程-线程模型，这种机制使得线程能够做更多的“功”，因为线程本身不需要进行上下文切换，而只是不停地取任务执行任务。上下文切换的工作交给了G（协程）来完成。这种灵活的调度机制使得Go能够更高效地利用系统资源，提高并发性能。

Goroutinue类似于空间换时间的策略，主要体现在两点，一是预先创建线程：Go运行时会根据CPU核心数预先创建一定数量的线程（M），虽然这可能导致某些线程闲置，从而造成资源浪费，但这种策略可以减少线程创建和销毁的开销，从而提高系统的并发性能；二是协程资源开销：相比于传统的进程-线程模型，协程本身也会占用一定的系统资源。虽然单个协程非常轻量，但是大量的协程仍会增加系统的开销。此外，如果协程被泄露，可能会导致系统资源得不到回收，从而可能引发内存溢出（OOM）。

### P
在Go运行时中，P（Processor）处理器充当G（goroutine）和M（machine）之间的桥梁。需要注意的是，P并不是指CPU，而是一个结构体变量（`src/runtime/runtime2.go:621`），负责管理和调度G与M之间的关系。

M从队列中取G执行。这个队列实际上是属于P的。每个P都有一个本地队列，用于存储待执行的G。此外，还有一个全局队列，用于存储所有P的本地队列无法容纳的G。当使用`go`关键字创建一个协程时，该协程并不一定会立即执行，而是会被放入某个P的本地队列中。P的本地队列是一个长度为256的数组。如果协程数量过多，以至于所有P的本地队列都已满，那么新创建的协程将被放入全局队列中。全局队列类似于一个双链表，理论上长度是无限的。

通过这种机制，Go运行时可以灵活地调度大量协程在有限的线程上执行，从而实现高效的并发执行。P作为G和M之间的中介，确保了协程能够在不同的线程之间切换，充分利用系统资源。这种设计使得Go语言能够在高并发场景下表现出卓越的性能，同时简化了并发编程的复杂性。
```go
type p struct {
	id          int32
	status      uint32 // one of pidle/prunning/...
	link        puintptr
	schedtick   uint32     // incremented on every scheduler call
	syscalltick uint32     // incremented on every system call
	sysmontick  sysmontick // last tick observed by sysmon
	m           muintptr   // back-link to associated m (nil if idle)
	mcache      *mcache
	pcache      pageCache
	raceprocctx uintptr

	deferpool    []*_defer // pool of available defer structs (see panic.go)
	deferpoolbuf [32]*_defer

	// Cache of goroutine ids, amortizes accesses to runtime·sched.goidgen.
	goidcache    uint64
	goidcacheend uint64

	// Queue of runnable goroutines. Accessed without lock.
	runqhead uint32
	runqtail uint32
	runq     [256]guintptr
	// runnext, if non-nil, is a runnable G that was ready'd by
	// the current G and should be run next instead of what's in
	// runq if there's time remaining in the running G's time
	// slice. It will inherit the time left in the current time
	// slice. If a set of goroutines is locked in a
	// communicate-and-wait pattern, this schedules that set as a
	// unit and eliminates the (potentially large) scheduling
	// latency that otherwise arises from adding the ready'd
	// goroutines to the end of the run queue.
	//
	// Note that while other P's may atomically CAS this to zero,
	// only the owner P can CAS it to a valid G.
	runnext guintptr

	// Available G's (status == Gdead)
	gFree struct {
		gList
		n int32
	}

	sudogcache []*sudog
	sudogbuf   [128]*sudog

	// Cache of mspan objects from the heap.
	mspancache struct {
		// We need an explicit length here because this field is used
		// in allocation codepaths where write barriers are not allowed,
		// and eliminating the write barrier/keeping it eliminated from
		// slice updates is tricky, more so than just managing the length
		// ourselves.
		len int
		buf [128]*mspan
	}

	// Cache of a single pinner object to reduce allocations from repeated
	// pinner creation.
	pinnerCache *pinner

	trace pTraceState

	palloc persistentAlloc // per-P to avoid mutex

	// The when field of the first entry on the timer heap.
	// This is 0 if the timer heap is empty.
	timer0When atomic.Int64

	// The earliest known nextwhen field of a timer with
	// timerModifiedEarlier status. Because the timer may have been
	// modified again, there need not be any timer with this value.
	// This is 0 if there are no timerModifiedEarlier timers.
	timerModifiedEarliest atomic.Int64

	// Per-P GC state
	gcAssistTime         int64 // Nanoseconds in assistAlloc
	gcFractionalMarkTime int64 // Nanoseconds in fractional mark worker (atomic)

	// limiterEvent tracks events for the GC CPU limiter.
	limiterEvent limiterEvent

	// gcMarkWorkerMode is the mode for the next mark worker to run in.
	// That is, this is used to communicate with the worker goroutine
	// selected for immediate execution by
	// gcController.findRunnableGCWorker. When scheduling other goroutines,
	// this field must be set to gcMarkWorkerNotWorker.
	gcMarkWorkerMode gcMarkWorkerMode
	// gcMarkWorkerStartTime is the nanotime() at which the most recent
	// mark worker started.
	gcMarkWorkerStartTime int64

	// gcw is this P's GC work buffer cache. The work buffer is
	// filled by write barriers, drained by mutator assists, and
	// disposed on certain GC state transitions.
	gcw gcWork

	// wbBuf is this P's GC write barrier buffer.
	//
	// TODO: Consider caching this in the running G.
	wbBuf wbBuf

	runSafePointFn uint32 // if 1, run sched.safePointFn at next safe point

	// statsSeq is a counter indicating whether this P is currently
	// writing any stats. Its value is even when not, odd when it is.
	statsSeq atomic.Uint32

	// Lock for timers. We normally access the timers while running
	// on this P, but the scheduler can also do it from a different P.
	timersLock mutex

	// Actions to take at some time. This is used to implement the
	// standard library's time package.
	// Must hold timersLock to access.
	timers []*timer

	// Number of timers in P's heap.
	numTimers atomic.Uint32

	// Number of timerDeleted timers in P's heap.
	deletedTimers atomic.Uint32

	// Race context used while executing timer functions.
	timerRaceCtx uintptr

	// maxStackScanDelta accumulates the amount of stack space held by
	// live goroutines (i.e. those eligible for stack scanning).
	// Flushed to gcController.maxStackScan once maxStackScanSlack
	// or -maxStackScanSlack is reached.
	maxStackScanDelta int64

	// gc-time statistics about current goroutines
	// Note that this differs from maxStackScan in that this
	// accumulates the actual stack observed to be used at GC time (hi - sp),
	// not an instantaneous measure of the total stack size that might need
	// to be scanned (hi - lo).
	scannedStackSize uint64 // stack size of goroutines scanned by this P
	scannedStacks    uint64 // number of goroutines scanned by this P

	// preempt is set to indicate that this P should be enter the
	// scheduler ASAP (regardless of what G is running on it).
	preempt bool

	// pageTraceBuf is a buffer for writing out page allocation/free/scavenge traces.
	//
	// Used only if GOEXPERIMENT=pagetrace.
	pageTraceBuf pageTraceBuf

	// Padding is no longer needed. False sharing is now not a worry because p is large enough
	// that its size class is an integer multiple of the cache line size (for any of our architectures).
}
```
### Schedt
上面我们讨论了GMP模型中G（goroutine）、M（machine）和P（Processor）各自的概念和作用。然而，我们还需要一个调度器来完成G、M、P之间的整合和协调。在Go运行时中，这个调度器被称为Sched（同样是个结构体，对应着`src/runtime/runtime2.go:774`），负责完成上述的调度过程。
Sched调度器的主要职责包括：
- 确定将新创建的协程放入哪个P的本地队列或者全局队列。Sched会根据当前的负载情况和资源分配策略，将新创建的协程分配给合适的P。

- 确定M从哪个P的本地队列中取出G执行。Sched会监控各个P的本地队列，以确保M能够从合适的P中取出G执行。当一个M完成了一个G的执行后，Sched会将该G重新放入工作队列，并指导M继续从其他P的本地队列中取出G执行。上文提到的P的全局队列对应着schedt的`runq`字段。

通过Sched调度器的协调，Go运行时可以实现G、M、P之间的高效整合，从而在高并发场景下实现卓越的性能。
```go
type schedt struct {
	goidgen   atomic.Uint64
	lastpoll  atomic.Int64 // time of last network poll, 0 if currently polling
	pollUntil atomic.Int64 // time to which current poll is sleeping

	lock mutex

	// When increasing nmidle, nmidlelocked, nmsys, or nmfreed, be
	// sure to call checkdead().

	midle        muintptr // idle m's waiting for work
	nmidle       int32    // number of idle m's waiting for work
	nmidlelocked int32    // number of locked m's waiting for work
	mnext        int64    // number of m's that have been created and next M ID
	maxmcount    int32    // maximum number of m's allowed (or die)
	nmsys        int32    // number of system m's not counted for deadlock
	nmfreed      int64    // cumulative number of freed m's

	ngsys atomic.Int32 // number of system goroutines

	pidle        puintptr // idle p's
	npidle       atomic.Int32
	nmspinning   atomic.Int32  // See "Worker thread parking/unparking" comment in proc.go.
	needspinning atomic.Uint32 // See "Delicate dance" comment in proc.go. Boolean. Must hold sched.lock to set to 1.

	// Global runnable queue.
	runq     gQueue
	runqsize int32

	// disable controls selective disabling of the scheduler.
	//
	// Use schedEnableUser to control this.
	//
	// disable is protected by sched.lock.
	disable struct {
		// user disables scheduling of user goroutines.
		user     bool
		runnable gQueue // pending runnable Gs
		n        int32  // length of runnable
	}

	// Global cache of dead G's.
	gFree struct {
		lock    mutex
		stack   gList // Gs with stacks
		noStack gList // Gs without stacks
		n       int32
	}

	// Central cache of sudog structs.
	sudoglock  mutex
	sudogcache *sudog

	// Central pool of available defer structs.
	deferlock mutex
	deferpool *_defer

	// freem is the list of m's waiting to be freed when their
	// m.exited is set. Linked through m.freelink.
	freem *m

	gcwaiting  atomic.Bool // gc is waiting to run
	stopwait   int32
	stopnote   note
	sysmonwait atomic.Bool
	sysmonnote note

	// safepointFn should be called on each P at the next GC
	// safepoint if p.runSafePointFn is set.
	safePointFn   func(*p)
	safePointWait int32
	safePointNote note

	profilehz int32 // cpu profiling rate

	procresizetime int64 // nanotime() of last change to gomaxprocs
	totaltime      int64 // ∫gomaxprocs dt up to procresizetime

	// sysmonlock protects sysmon's actions on the runtime.
	//
	// Acquire and hold this mutex to block sysmon from interacting
	// with the rest of the runtime.
	sysmonlock mutex

	// timeToRun is a distribution of scheduling latencies, defined
	// as the sum of time a G spends in the _Grunnable state before
	// it transitions to _Grunning.
	timeToRun timeHistogram

	// idleTime is the total CPU time Ps have "spent" idle.
	//
	// Reset on each GC cycle.
	idleTime atomic.Int64

	// totalMutexWaitTime is the sum of time goroutines have spent in _Gwaiting
	// with a waitreason of the form waitReasonSync{RW,}Mutex{R,}Lock.
	totalMutexWaitTime atomic.Int64
}
```
## 调度过程
在runtime2.go文件中有几个全局变量，分别是allm、gomaxprocs、ncpu、sched、newprocs、allp；下面分别解释一下它们的含义及作用。
在Go运行时中，以下变量和结构体用于管理和调度G（goroutine）、M（machine）和P（Processor）之间的关系：

- `allm`：一个指向M（machine）链表头部的指针。所有的M实例被组织成一个链表结构，以便在程序运行过程中方便地添加和删除M实例。

- `gomaxprocs`：一个整数变量，表示允许同时运行的最大操作系统线程数（即M的数量）。默认情况下，它的值等于系统的CPU核心数。您可以通过设置`GOMAXPROCS`环境变量或使用`runtime.GOMAXPROCS()`函数来调整此值。

- `ncpu`：一个整数变量，表示系统的CPU核心数。它在程序启动时被初始化，并在整个程序运行过程中保持不变。

- `sched`：一个结构体，表示Go运行时的调度器。它负责协调G、M和P之间的关系，包括将新创建的协程分配给合适的P，以及指导M从合适的P的本地队列中取出G执行。

- `newprocs`：一个整数变量，用于在调整`gomaxprocs`值时暂存新的最大并发线程数。当`newprocs`的值与`gomaxprocs`不同时，Go运行时会在下一个调度周期中更新`gomaxprocs`的值。

- `allp`：一个切片，用于存储所有的P（Processor）实例。在程序运行过程中，P的数量可能会发生变化，例如，当您调整`GOMAXPROCS`值时。使用切片可以方便地调整P的数量，同时保持对所有P实例的引用。

所有的调度都是由sched变量完成的，在进程启动的时候，会把主线程分配到某个m上，当有新的goroutinue创建的时候会随机分配到p的某个队列上，如果选择的p满了，再选择其它的p，如果都满了则会放到全局队列上。总结一下调度过程：

1. 创建G：当使用`go`关键字创建一个新的协程时，`newproc`函数会被调用。在`newproc`函数中，会创建一个新的G实例，并将其与待执行的函数关联。

2. 将G放入队列：Sched调度器会将新创建的G尝试放入与当前正在执行的G关联的P的本地队列。如果当前P的本地队列已满，新创建的G会被放入全局队列。

3. M从队列中取G：Sched调度器会指导M从关联的P的本地队列中取出G执行。如果本地队列为空，M会尝试从全局队列或其他P的本地队列中偷取G。

4. 执行G：M会执行取出的G，直到G执行完成或遇到阻塞操作（如I/O操作）。

5. G执行完成：当G执行完成后，Sched调度器会将G标记为已完成。如果G没有其他引用，它会在垃圾回收过程中被回收。与此同时，Sched调度器会指导M继续从关联的P的本地队列中取出下一个G执行。

6. G阻塞：当G遇到阻塞操作时（如IO操作、系统调用、sleep等），Sched调度器会将阻塞的G状态从Grunning切换到Gwaitin状态并放入原先所在的P（Processor）的本地队列或全局队列中，以便在阻塞操作完成后能够继续执行。同时，M会尝试从P的本地队列中取出另一个G执行。在这种情况下，Go运行时可能会创建一个新的M来执行其他G，以保持并发性能。

7. G解除阻塞：当阻塞操作完成后，Sched调度器会将阻塞G状态从Gwaiting状态切换到Grunnable状态，等待再次被调度到M上运行。

在整个调度过程中，Sched调度器负责管理G与P之间的交互，如将G放入P的本地队列以及从P的本地队列中取出G执行。同时，Sched调度器也负责协调P与M之间的交互，如指导M从关联的P的本地队列中取出G执行，以及在G阻塞时将G与M解除关联。

通过Sched调度器和GMP模型的协同工作，Go运行时可以实现高并发性能，同时简化了并发编程的复杂性。