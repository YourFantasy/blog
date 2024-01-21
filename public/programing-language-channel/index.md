# Golang中channel底层实现原理


<!--more-->

## 前言
并发编程是日常开发中经常需要使用到的，在Java中jdk提供了功能丰富的
并发库和并发原语支持，包括线程池、各种锁机制，并发安全的数据结构等，开发者可以以比较低的成本来进行并发编程。但是在golang里面，更并发相关的一些组件或者说能力相对来说就没有Java中那么丰富了，比如说golang中就没有提供线程池这个能力。golang遵循的哲学是`使用通信来共享内存，而不是使用共享内存来通信。`，简单来说在golang中多线程之间要进行数据共享的时候，并不是通过共享内存，去对共享内存并发读写实现的，golang提供了一种名为channel的能力，多协程之间通过channle传输数据做并发控制和数据同步。