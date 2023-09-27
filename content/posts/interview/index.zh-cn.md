---
title: "面试复盘"
subtitle: ""
date: 2023-07-01T08:59:43+08:00
lastmod: 2023-07-01T08:59:43+08:00
draft: true
author: "Bard"
authorLink: "www.bardblog.cn"
description: "记录社招面试过程及复盘"
license: ""
images: []

tags: ["MySQL","InnoDB","Redis","Kafka","Algorithm"]
categories: ["technology","interview"]

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
# 项目总结

## 底层存储设计

### 数据结构

所有的关系链数据都是使用redis的hash数据结构来存储的，设计了一个通用的适配层，高性能、安全、多租户的通用存储系统。

### 背景

- 从qq群历史架构->discord->需要支持千万级关系链的读写能力,关系链复杂，超大群，热点效应。通用、高并发、安全、百万人量级关系链系统。
- 构建一个存储适配层，read和write。write会聚合排队写

#### redis底层设计

- 首先介绍一下业务背景，几个核心的关系链场景基本概念，解释为啥要使用redis作为db使用，然后解释说明为啥要用redis的hash这种数据结构，排除法来选择。以频道下的人这个关系链存储来展开，再引申到key和热 key 问题怎么解决？
- 以频道ID作为key，filed是成员id，filed对应的value是成员基本信息，昵称、角色等业务信息，是pb序列化后的结果。
- 频道初始化的时候有两个hash结构的key，一个称之为member，一个称之为info，member很大，info很小，存储频道业务和元数据路由信息。每个member表分配beginIndex,endIndex。
- 拆表/合并策略：类似于二叉树的结点分裂，每次一分为二，计算qq号的hash值，分配到左区间还是右区间，并更新路由信息，大概耗时90多ms；如果发现某个子表的数量很小，尝试和它的另一半合并，并更新路由信息，大概耗时40ms。
- 版本号控制，全局有一个版本号，每个子表也有一个版本号；控制当前的版本，版本号是递增的，初始化的时候是0，每次数据更新或者分裂都会更新版本号。
- 支持多租户，上述只是以频道下这个人作为例子，实际上我们的这套存储设计抽象是跟业务无关的，安全、抽象，支持多租户0成本接入。划分号段，实现水平扩展能力。

Gt member 目前是4GB*32分片6副本，目前redis实例的均值qps是60w左右，平均一个分片是60w/32/6=3000qps，分片峰值qps是7k，单key是1.2MB大小

单分片负载最高的是20%左右

#### 在redis之上构建的本地缓存

- 缓存子表，没台机器存储全量大频道数据，目前占用8G左右，三大策略保证一致性；

    ```shell
    1.广播更新（内网，增量）；2后台定时轮询子表版本号，版本号落后，更新数据（全量）；3；缓存命中抽样上报，低于阈值触发熔断（降级熔断）重建缓存。
    ```

- 排队合并写入，对于加频道/退频道请求，会本地排队聚合写入，减少广播次数。请求合并.

- 容器化部署，自动伸缩,128GB*24=3TB内存， 内存使用率54%，cpu使用率50%，写tps 3000多，平均每台机器100多写入请求

- 同时缓存Info和子表数据，精细化构建缓存和更新，减少缓存失效次数。使用合并策略，一致性hash算法路由到一台机器从redis拉取数据构建更新缓存，减少拉取流量和热key问题。写操作读取不走缓存，直接穿透db。

## 私密子频道鉴权模型优化

### 背景

历史原因导致私密子频道鉴权会扩散查私密子频道成员，当私密子频道活动比较多的时候（触发大量读鉴权），叠加多个写操作。会对底层产生较大压力，触发告警。热key问题。优化 `人-频道`、`人-子频道`、`人-身份组`、`子频道-身份组`，人的身份组和子频道身份组取交。

### 优化

- 优化人的频道这个存储，将反向关系链做准，以反向关系链鉴权人在不在频道，热点问题变成散列问题。
- 存储模型优化：历史原因导致，鉴权模型私密子频道+身份组+私密子频道下的人+身份组下的人，干掉私密子频道下的人，把私密子频道也理解为一个隐藏身份组，梳理上下游服务，读写改造灰度、历史数据迁移，发布节奏控制，风险把控
- 基于关系链存储构建二级cache缓存：梳理业务，细化人和子频道纬度，哪些地方写会影响缓存，子频道-身份组（本地）和人-身份组（redis）纬度的缓存。细化写逻辑。热点问题变成散列问题，鉴权读缓存和本地比较不一致则鉴权扩散。减少无效鉴权，精细化控制。用户纬度的子频道seq和全局的子频道纬度seq作对比。所有可能影响的地方入口写。人/子频道鉴权.seq内容是权限位。构建二级缓存。

## 事件中心拉平

### 背景

王者荣耀等超大频道运营活动导致一下子感知到很多人，推送信令触发拉取操作，千人千面对后台关系链产生较大压力。

### 优化

### 限流

减少事件的数量，在写服务入口处限制写的频率，使用令牌桶算法，进而减少事件的数量，缓解消息积压。，事件推送采用漏桶算法平滑推送

#### 削峰拉平

- redis实现延迟队列削峰拉平

```lua
local score = redis.call('ZSCORE', KEYS[1], KEYS[2])
	if (score == false or score %% %d > 0)
	then
		score = ARGV[1]
		redis.call('ZADD', KEYS[1], ARGV[1], KEYS[2])
	end
	redis.call('ZADD', KEYS[2], score, ARGV[2])
	return redis.call('EXPIRE', KEYS[2], ARGV[3])`
# 三类key
1.KEYS[1]：taskKey（zset):单个，任务集合
score：当前时间戳
member:guild_id+even_type+ip

2.KEYS[2]:eventKeys(zset):多个，具体的事件,和taskKey中的member对应
score: KEYS[1]中的时间戳
member:事件的内容序列化后的内容

3.last_consumer_score: 单个，每次从taskKey取任务之前拉取，消费完成后设置。

```

- 每300ms从taskKey取任务，再从eventKeys中取任务，根据事件类型进行合并分包写到一个下游kafka，5000个人一个包。每次执行完任务后更新last_consumer_score和并从task中删除和zset中移除
- 兜底逻辑：考虑到服务宕机等问题，可能某台机器写到taskKey的任务没来得及消费，这个时候需要另外一个线程执行兜底逻辑消费未被消费的任务，会使用分布式锁上锁，防止多台机器重复消费。
- 下游服务消费写入的kafka执行推送任务，复用大群通道推送，限流控速。

#### 非关键信息增量推送

对于频道名称或者其它不是很关键的信息，直接走增量推送，把数据直接推给客户端，不用触发拉取。 推失败也没关系客户度会有补偿逻辑。

## ID转换服务重写

### 背景

底层id转换服务，请求量大上游多，数据量key超多，对服务稳定性以及耗时有严苛要求。设计一个缓存的要点

- 设置缓存占用大小，防止无限制增长导致oom
- 分片策略，减少锁粒度
- 合适的hash算法，减少hash碰撞。
- singleflight策略，减少缓存击穿
- 缓存淘汰策略，缓存过期时间。
- 数据结构高效，时间复杂度和空间复杂度的平衡。
- 打点监控，缓存击穿率，缓存命中率监控告警。
- 缓存持久化，缓存预热。

### 现状

- 单机缓存构建耗时过长，10分钟后机器才能提供服务，且随着id数增长，耗时会越来越大。
- bigcache占用空间过大，存在瓶颈（bigcache空间占用由map+对象序列化后内存消耗组成），线上30GB内存最多存储2亿数据。
- 服务中大量使用int转string、pb打解包等方法，以及不合理的打点，影响整体性能。

### 优化

- 使用自己实现的cache代替原来的bigcache，一亿个键值对，1亿数据占用不到1.7GB，64GB机器可支撑30亿正反数据（15亿账号）

  ```shell
  1.本地cache 使用三个数组实现，单条kv数据是8（key)+8(val)+1(时间）=17个字节，节省空间，内存更紧凑，相比于map空洞更少
  2.分片设计，根据hash算法把key hash到不同分片,降低锁粒度，目前是3w个分片，每个分片3000多条数据。
  3.读取使用二分查找的方式查找数据，单分片单次查找速度极快33ns，内置map是20ns，bigcache是109ns。
  4.基本数据类型，省去序列化反序列化过程，直存直取。后台任务定时扫描清理老数据，腾出空间
  5.使用插入排序的方式更新数据，基本有序数据插入排序时间复杂度很快;触发容量上限会删除最老的数据，没有触发的话会按照步长扩容。
  6.使用cos作为持久化数据（加密+压缩，压缩率60%）每天随机一台机器定时dump一次数据到56个cos小文件，每个文件都有hash校验和。
  7.服务启动并发拉取cos数据还原加载本地内存数据，根据hash校验和剔除掉有问题文件，4s内恢复。
  8.读到新数据广播兄弟结点更新，最大程度保证各个机器数据完备性。
  ```

## 大群通道

- 以人纬度的缓存，增量+全量更新逻辑，用户消息驱动+kafka增量更新消息空洞补齐+后台定时扫描全量更新，保证数据一致性

```go
cache1:	key：guild_id+sub_id:value 5000个子表 // 每个频道每个子表的全量数据
cache2:	key:guild_id+uin:value：人的信息 // 缓存人在频道里面的信息，主要是权限数据
cach3:	key:uin:value:map[guild_id][sub_id]  //人在每个频道所属的子表信息
```

- 消息以人为纬度聚合推送（减少下行流量）+消息精简+消息分级，高优先级先推，低优先级后推。减少推送次数+减少推送流量。
- 消息精简，焦点上报，客户端维护一份焦点，在推送消息的时候把人的焦点信息也推送下去，客户端判断焦点和自己本地较低是否一致，不一致则上报焦点，一致则不上报，避免无效频繁上报。
- token机制，atall的时候，使用token鉴权，减少拉取消息对于关系链的请求压力。构建以人纬度的缓存，做增量和全量更新。

## 微服务治理

### 背景

目前4个后台组总共有600个微服务，对于底层的核心服务存在很多不合理调用情况，微服务拆分过细，接口设计不合理等问题。继续优化改造，降低风险。主要以下几个手段

### 治理

- 大流量底层服务推动微服务治理，抓大放小，减少重复调用，推动上下游改造。把控进度和风险。
- 对于大而全的接口，拆分细化，提供轻量级的接口，逐步平滑迁移。
- 微服务合并，将功能/代码类似的微服务合并到一个服务，减少微服务数量和链路复杂性，节省机器资源。
- 核心大流量服务申请调用需要走申请，需要详细说明调用目的以及调用频率，管控混乱调用，
- 设计不合理代码性能优化，重构，池化技术、缓存、请求合并。
- 推动上游服务请求合并&增加缓存，优化性能节省机器资源。

## 海量服务总结

- 架构合理：底层存储选型是否合理，数据结构/表设计是否合理，数据/扩散比模型推演,分库分表，存储拆分。
- 横向/纵向扩容：系统具有较好的扩展能力，留足buffer，自动扩缩容，减少人工介入。
- 池化技术：代码层面使用池化技术，包括连接池/协程池/对象池，池化技术，复用思想。
- gc调优；gc压力过大，需要分析优化，减少内存碎片，减少gc频率，减少gc次数。
- 锁优化，减少锁粒度，分片锁而不是全局锁，读写锁而不是互斥锁，乐观锁而不是悲观锁。
- 缓存：缓存预热，饿加载方式，同时尽量保证缓存一致性保，多级缓存。
- 全链路监控告警：包括pass、拨测、服务指标、耗时波动、请求量波动、打点监控等全链路无死角告警。监控要求全面且准确，并且针对告警有应对预案。告警包括单机和大盘的指标。
- 并发/异步：代码层面能够并发的并发，能够异步的异步，使用mq等方式解耦。
- 链路优化/精简，微服务架构优化，轻量级接口，减少无效请求和调用，请求聚合，减少重复请求。
- 限流/降级策略，非核心场景降级开关，避免阻塞主流程，保证主场景可用。
- 接口重试/幂等：失败重试，但是要注意重试雪崩，保证接口幂等，对冲重试。
- 服务全链路压测：事前压测，事前分析系统短板，事前优化。
- 削峰/限流策略：峰值流量削峰限流，限流防止打垮db，有损减少核心场景不可用。
- 服务发布，ci/cd，观测指标，灰度发布，关键日志、监控打点，紧急回滚策略。
- 容灾：同地多机房，异地部署，防止全死全活。
- 服务接口数据自修复能力，系统健壮性。数据压缩，cpu和io权衡。
- 降低系统耦合度，接口单一职责，接口拆分。避免大而全接口，微服务改造。

## 方法论

- 做任何事之前先想再做，在做的过程中继续想，要主动思考，发现问题，不要做一个被动的执行者，磨刀不误砍柴工，谋定而后动。
- 想到了一个方案或者解法不要冲动马上去做，而是要多讨论，集思广益，有没有其他的方法，更好的方法？虽然最后只会选用一个方法去做，但这个思考的过程对自己来说是个很好的沉淀，在未来的某一天可能就用上了。
- 做任何事之前都需要评估下风险、成本，列出一个roadmap，各个阶段的风险点是什么，涉及到的上下游，是否知会到了，拒绝不可控，遍历潜在的风险，根据墨菲定律，可能出问题的地方一定会出问题，不要放过每一个细节。
- 事有轻重缓急缓解，四象限法则，紧急重要的事一定要最高优先级去做，不紧急不重要的事情绝对不去做，第一象限和第四象限占少数，生活中大多数事第二三象限的事，一般来说主要精力放在紧急不重要的事情上，久久为功，不要让重要的事变成紧急的事。
- 学会合理的申请和协调资源，包括但不限于人力资源、时间资源等，要做成一件事，一个人是不行的，需要很多资源的支持，给资源才能做成事，协调各方资源，定一个计划表，只有一个okr把事情做成。
- 主人翁意识，多思考，多总结，推动上下游去做事，积极主动。多记录总结，每件事做完之后总结复盘一下得与失，成长与思考。


# 面试复盘

## 微派（挂）

### 20230707 微派一面（挂）

- bitmap数据结构底层实现，最大2^32个bit位。占用内存空间位512MB（8位占用1B）

$$
2^{32}bit=2^{10} \times 2^{10} \times 2^{10} \times 2^{3} \div 2 =1GB \div2=512MB
$$

**以下是用go语言实现的位图：**

```go
var outOfRange = errors.New("out of range")

type BitMap struct {
	bits []byte
	size int
}

// NewBitMap 创建一个bitmap
// size bitmap能存储最大的位
func NewBitMap(size int) *BitMap {
	return &BitMap{
		bits: make([]byte, (size+7)/8), // 向上取整
		size: size,
	}
}

// SetBit 设置指定位的bit值
func (b *BitMap) SetBit(index int, val bool) error {
	if index < 0 || index >= len(b.bits)*8 {
		return outOfRange
	}
	byteIndex := index / 8
	bitIndex := index % 8
	if val { // 1
		b.bits[byteIndex] |= 1 << bitIndex
	} else { // 0
		b.bits[byteIndex] &= ^(1 << bitIndex)
	}
	return nil
}

// GetBit 获取位图指定位置是否是1
func (b *BitMap) GetBit(index int) (bool, error) {
	if index < 0 || index >= len(b.bits)*8 {
		return false, outOfRange
	}
	byteIndex := index / 8
	bitIndex := index % 8
	return b.bits[byteIndex]&(1<<bitIndex) != 0, nil
}

// CountRange 获取位图中指定范围内的位的数量，返回的是该范围内值为1的位的数量。
func (b *BitMap) CountRange(begin, end int) (int, error) {
	if begin > end || begin < 0 || end >= len(b.bits)*8 {
		return 0, outOfRange
	}
	cnt := 0
	for i := begin; i <= end; i++ {
		if res, _ := b.GetBit(i); res { // 入口处已经检查参数判断，所以这里不用判断了，可以忽略error
			cnt++
		}
	}
	return cnt, nil
}

// CountAll 统计整个位图中值为1的位的数量
func (b *BitMap) CountAll() int {
	res, _ := b.CountRange(0, b.size-1)
	return res
}

```

- 从0～n-1这n个数中随机选择m个数，m<=n，要求概率相等，选中的数不能重复

```go
// m<=n;从0~n-1这个n个数中随机选出m个数，要求等概率，并且选出的m个数不能重复
// 蓄水池算法，数学归纳法证明
func getMRandomDigits(n, m int) []int {
	res := make([]int, m)
	for i := 0; i < m; i++ {
		res[i] = i
	}
	rand.Seed(time.Now().UnixNano())
	for i := m; i < n; i++ {
		j := rand.Intn(i + 1)
		if j < m {
			res[j] = i
		}
	}
	return res
}
```

- redis怎么减少内存占用空间？

> 1. 选用合适的数据结构来存储，比如可以用bitmap来表示大量唯一值，HyperLogLog统计唯一元素值的数量（基于数学概率，有一定误差，适用于海量数据统计）。
> 2. 使用内存淘汰策略，淘汰长期不使用的键。
> 3. 将同类型的元素聚合在Hash中，而不是作为键单独存储，减少键值本身的消耗，节省内存空间。
> 4. 优化键名，防止键名过长。
> 5. 使用LZF压缩，开启压缩，压缩和解压是在redis完成的，用户无感知。

## 美团（offer)

### 20230711 美团一面（过）


-  redis底层数据结构理解及原理了解?
-  知识的广度及深度需要提高?
-  发布如何从技术层面保证不出问题？

**买卖股票的最佳时机：**

```go
func maxProfit(prices []int) int{
		if len(prices)<2{
				return 0
		}
		buyPrice:=prices[0]
		res:=0
		for i:=1;i<len(prices);i++{
				if prices[i]<buyPrice{
						buyPrice=prices[i]
				}
				res=max(res,prices[i]-buyPrice)
		} 
		return res
}

func max(a,b int)int{
	if a<b{
		return b
	}
	return a
}
```

### 20230719 美团二面（过）

聊项目：纯聊项目，聊了140分钟.....

## 拼多多(offer)

### 20230711 拼多多一面（过）

聊项目，30min

- 场景设计题：如何拉取频道成员，按照加入时间排序？zset
- 除了hash，为啥不用其他的数据结构？
- 找到附近的人，怎么做？用什么redis 数据结构？Geo
- 对于redis的广度理解不够
- 函数延迟调用？

**一个整数数组，除了一个数，其他数都出现了两次，找出这个只出现一次的数：**

```go
func findUniqueNum(nums []int) int{
  res:=nums[0]
  for i:=1;i<len(nums);i++{
    res^=nums[i]
  }
  return res
}
```

### 20230716 拼多多二面（过）

- 万人大群抢红包怎么处理？读扩散+写扩散模式
- kafka为什么快?

> Kafka 是一个高性能、可扩展的分布式消息队列系统，它之所以能够实现高吞吐量和低延迟，主要归功于以下几个设计原则和优化策略：
>
> 1. 高效的磁盘存储和顺序读写：Kafka 将消息存储在磁盘上，并利用操作系统的 page cache 进行缓存。Kafka 的消息存储是顺序的，这意味着它可以充分利用磁盘的顺序读写性能。顺序读写比随机读写更快，因为磁盘的寻道时间得到了显著减少。
> 2. 零拷贝技术：Kafka 使用了零拷贝技术（zero-copy）来减少数据在内核空间和用户空间之间的拷贝次数。这可以降低 CPU 使用率，减少上下文切换，从而提高性能。
> 3. 批量处理：Kafka 支持批量发送和消费消息。生产者可以将多个消息打包成一个批次，一次性发送给 Kafka。同样，消费者也可以一次性从 Kafka 获取多个消息。批量处理可以减少网络开销和磁盘 I/O，从而提高吞吐量。
> 4. 分区和多副本：Kafka 的主题可以分为多个分区，每个分区可以独立地存储和处理消息。这使得 Kafka 可以在多个服务器上并行处理消息，从而实现水平扩展。此外，Kafka 还支持多副本，可以提高数据的可靠性和可用性。
> 5. 消息压缩：Kafka 支持对消息进行压缩，以减少网络传输和磁盘存储的开销。压缩可以降低 I/O 压力，提高吞吐量。
> 6. 消费者组和消费者位移：Kafka 使用消费者组和消费者位移来实现高效的消息消费。消费者组可以实现负载均衡，多个消费者可以共同消费一个主题。消费者位移记录了消费者在每个分区中消费的位置，这使得消费者可以随时恢复消费进度，而无需查询 Kafka。
> 7. 异步处理：Kafka 的生产者和消费者都支持异步处理。生产者可以在不等待服务器响应的情况下发送消息，消费者可以在不等待处理完成的情况下获取消息。异步处理可以降低延迟，提高吞吐量。
>
> 综上所述，Kafka 通过高效的磁盘存储、零拷贝技术、批量处理、分区和多副本、消息压缩、消费者组和消费者位移以及异步处理等设计原则和优化策略，实现了高吞吐量和低延迟的消息传输。

- redis为什么这么快？

> Redis 是一个高性能的键值存储系统，它之所以能够实现高速读写，主要归功于以下几个设计原则和优化策略：
>
> 1. 内存存储：Redis 将所有数据存储在内存中，这意味着它可以避免磁盘 I/O 带来的性能开销。内存访问速度远远快于磁盘，因此 Redis 能够实现高速读写。
> 2. 单线程模型：Redis 使用单线程模型处理客户端请求，这意味着它不需要处理多线程之间的同步和锁竞争问题。单线程模型简化了 Redis 的设计，降低了上下文切换和锁竞争带来的性能开销。
> 3. 高效的数据结构：Redis 支持多种高效的数据结构，如字符串、列表、集合、哈希表和有序集合。这些数据结构在内存中的表示非常紧凑，且支持高效的操作。例如，Redis 的哈希表实现了自动扩容和收缩，以保持高效的内存使用和性能。
> 4. 事件驱动模型：Redis 使用事件驱动模型处理网络 I/O，这使得它可以高效地处理大量并发连接。事件驱动模型避免了线程阻塞和上下文切换带来的性能开销。
> 5. 管道化（Pipelining）：Redis 支持管道化，这意味着客户端可以一次性发送多个命令，而无需等待每个命令的响应。管道化可以降低网络延迟，提高吞吐量。
> 6. 优化的内存管理：Redis 使用自定义的内存管理器和内存分配器，以减少内存碎片和提高内存使用效率。此外，Redis 还支持内存回收策略，如 LRU（最近最少使用）算法，以在内存不足时自动删除不常用的数据。
> 7. 持久化策略：虽然 Redis 主要是内存存储，但它也支持持久化策略，如 RDB 快照和 AOF 日志。这些持久化策略可以在后台异步执行，以减少对性能的影响。
>
> 综上所述，Redis 通过内存存储、单线程模型、高效的数据结构、事件驱动模型、管道化、优化的内存管理和持久化策略等设计原则和优化策略，实现了高速读写。然而，这些优势也带来了一些限制，如内存容量限制和单线程处理能力限制。在实际应用中，需要根据具体需求权衡 Redis 的优势和限制

- 基于redis协议实现hbase协议？代理
- 写一个100%死锁的代码

> ```go
> func deadLock(){
> var wg sync.WaitGroup
> wg.Add(2)
> ch1,ch2:=make(chan struct{},chan struct{})
> go func(){
>  defer wg.Done()
>  <-ch1
>  ch2<-struct{}{}
> }()
> 
> go func(){
>  defer wg.Done()
>  <-ch2
>  ch1<-struct{}{}
> }()
> wg.Wait()
> }
> ```
>
> 

### 20230723 拼多多三面（过）

- 聊项目，难点
- 为什么来上海，996扛得住吗？在腾讯目前看起来很好，时日尚短为啥跳槽
- 给定一个长度为n的数组nums，求前k（1<=k<=n）个元素的中位数，如果k是偶数，取中间两个数的平均数四舍五入，输出是一个长度为n的数组，result[k-1]代表nums前k个元素的中位数

> ```go
> // 时间复杂度：O(n^2*logn)
> // 空间复杂度：O(n)
> func getMid1(nums []int) []int {
> 	res := make([]int, len(nums))
> 	for i := 0; i < len(nums); i++ {
> 		tmp := make([]int, i+1)
> 		for j := 0; j < len(tmp); j++ {
> 			tmp[j] = nums[j]
> 		}
> 		sort.Ints(tmp)
> 		if (i+1)&1 == 0 {
> 			sum := tmp[len(tmp)/2] + tmp[(len(tmp)-1)/2]
> 			mid := sum / 2
> 			if sum%2 != 0 {
> 				mid += 1
> 			}
> 			res[i] = mid
> 		} else {
> 			res[i] = tmp[len(tmp)/2]
> 		}
> 	}
> 	return res
> }
> 
> // 时间复杂度：O(n^2)
> // 空间复杂度：O(1)
> func getMid2(nums []int) []int {
> 	res := make([]int, len(nums))
> 	for i := 0; i < len(nums); i++ {
> 		index := findBigger(nums, i, nums[i])
> 		if index != -1 {
> 			tmp := nums[i]
> 			for j := i; j > index; j-- {
> 				nums[j] = nums[j-1]
> 			}
> 			nums[index] = tmp
> 		}
> 		if (i+1)&1 == 0 {
> 			sum := nums[(i+1)/2] + nums[i/2]
> 			mid := sum / 2
> 			if sum%2 != 0 {
> 				mid += 1
> 			}
> 			res[i] = mid
> 		} else {
> 			res[i] = nums[i/2]
> 		}
> 	}
> 	return res
> }
> 
> // 时间复杂度：O(log(n!)趋近于O(nlogn)
> // 空间复杂度：O(n)
> func getMid3(nums []int) []int {
> 	minH, maxH := newMinHeap(len(nums)), newMaxHeap(len(nums))
> 	res := make([]int, len(nums))
> 	for i := 0; i < len(nums); i++ {
> 		if nums[i] < minH.Peek() {
> 			maxH.Add(nums[i])
> 		} else {
> 			minH.Add(nums[i])
> 		}
> 		if maxH.Peek() > minH.Peek() {
> 			tmp := maxH.Pop()
> 			maxH.Add(minH.Pop())
> 			minH.Add(tmp)
> 		}
> 		if maxH.num > minH.num+1 {
> 			minH.Add(maxH.Pop())
> 		}
> 		if maxH.num < minH.num {
> 			maxH.Add(minH.Pop())
> 		}
> 		if (i+1)&1 == 0 {
> 			sum := maxH.Peek() + minH.Peek()+1
> 			res[i] = sum / 2
> 		} else {
> 			res[i] = maxH.Peek()
> 		}
> 	}
> 	return res
> }
> 
> func findBigger(nums []int, n int, target int) int {
> 	if n == 0 || nums[n-1] <= target {
> 		return -1
> 	}
> 	i, j := 0, n-1
> 	for i < j {
> 		m := i + (j-i)/2
> 		if nums[m] > target {
> 			j = m
> 		} else {
> 			i = m + 1
> 		}
> 	}
> 	return i
> }
> 
> 
> func (m *minHeap) Add(val int) {
> 	if m.num < len(m.elements) {
> 		m.elements[m.num] = val
> 
> 	} else {
> 		m.elements = append(m.elements, val)
> 	}
> 	m.num += 1
> 	m.up(m.num - 1)
> }
> 
> func (m *minHeap) Peek() int {
> 	if m.num == 0 {
> 		return math.MaxInt
> 	}
> 	return m.elements[0]
> }
> 
> func (m *minHeap) Pop() int {
> 	if m.num == 0 {
> 		return math.MaxInt
> 	}
> 	val := m.elements[0]
> 	m.elements[0] = m.elements[m.num-1]
> 	m.num -= 1
> 	m.down(0)
> 	return val
> }
> 
> func (m *maxHeap) Add(val int) {
> 	if m.num < len(m.elements) {
> 		m.elements[m.num] = val
> 
> 	} else {
> 		m.elements = append(m.elements, val)
> 	}
> 	m.num += 1
> 	m.up(m.num - 1)
> }
> 
> func (m *maxHeap) Pop() int {
> 	if m.num == 0 {
> 		return math.MinInt
> 	}
> 	val := m.elements[0]
> 	m.elements[0] = m.elements[m.num-1]
> 	m.num -= 1
> 	m.down(0)
> 	return val
> }
> 
> func (m *maxHeap) Peek() int {
> 	if m.num == 0 {
> 		return math.MinInt
> 	}
> 	return m.elements[0]
> }
> 
> func (m *maxHeap) up(index int) {
> 	for index > 0 && m.elements[index] > m.elements[(index-1)/2] {
> 		m.elements[index], m.elements[(index-1)/2] = m.elements[(index-1)/2], m.elements[index]
> 		index = (index - 1) / 2
> 	}
> }
> 
> func (m *maxHeap) down(index int) {
> 	for 2*index+1 < m.num {
> 		j := 2*index + 1
> 		if j+1 < m.num && m.elements[j+1] > m.elements[j] {
> 			j = j + 1
> 		}
> 		if m.elements[index] >= m.elements[j] {
> 			break
> 		}
> 		m.elements[index], m.elements[j] = m.elements[j], m.elements[index]
> 		index = j
> 	}
> }
> 
> func (m *minHeap) up(index int) {
> 	for index > 0 && m.elements[index] < m.elements[(index-1)/2] {
> 		m.elements[index], m.elements[(index-1)/2] = m.elements[(index-1)/2], m.elements[index]
> 		index = (index - 1) / 2
> 	}
> }
> 
> func (m *minHeap) down(index int) {
> 	for 2*index+1 < m.num {
> 		j := 2*index + 1
> 		if j+1 < m.num && m.elements[j+1] < m.elements[j] {
> 			j = j + 1
> 		}
> 		if m.elements[index] <= m.elements[j] {
> 			break
> 		}
> 		m.elements[index], m.elements[j] = m.elements[j], m.elements[index]
> 		index = j
> 	}
> }
> 
> func newMinHeap(n int) *minHeap {
> 	return &minHeap{
> 		elements: make([]int, n),
> 		num:      0,
> 	}
> }
> 
> func newMaxHeap(n int) *maxHeap {
> 	return &maxHeap{
> 		elements: make([]int, n),
> 		num:      0,
> 	}
> }
> 
> type minHeap struct {
> 	elements []int
> 	num      int
> }
> 
> type maxHeap struct {
> 	elements []int
> 	num      int
> }
> ```
>
> 



## 最右

### 20230712 最右一面（挂）

- 场景设计题：有一个热榜帖子，每分钟,刷新10条帖子，最近24小时热度最高的100个帖子：使用redis的zet做延迟队列，时间戳作为score，存储任务，然后另外一个redis的zset存储这个

  - 延迟队列具体怎么做？

  > ```lua
  > --delayQueue:
  > --key:hashTag+merge_messages
  > --filed:guild_id:event_id:ip:hashTag
  > --score:时间戳
  > --workQueue:带过期时间
  > --key:guild_id:event_id:ip:hashTag
  > --filed:data（kafka数据）
  > --score: 最后一个score
  > local score = redis.call('ZSCORE', KEYS[1], KEYS[2])
  > if (score == false or score %% %d > 0)
  > then
  > score = ARGV[1]
  > redis.call('ZADD', KEYS[1], ARGV[1], KEYS[2])
  > end
  > redis.call('ZADD', KEYS[2], score, ARGV[2])
  > return redis.call('EXPIRE', KEYS[2], ARGV[3])
  > ```
  >
  > 

## 百度

### 20230713 百度一面（过）

- 表分裂的时候数据读写怎么办？表分裂比较低频，分裂过程大概100ms以内
- 对于其它技术了解的怎么样？

**合并n个有序链表，并对结果去重:**

```go
type listNode struct{
  val int
  next *listNode
}

func mergeListNodes(nodes []*listNode,l,r int) *listNode{
  if l>r{
    return ni
  }
  if l==r{
    return nodes[l]
  }
  m:=l+(r-l)/2
  h1,h2:=mergeListNodes(nodes,l,m),mergeListNodes(nodes,m+1,r)
  return merge(h1,h2)
}

func merge(h1,h2 *listNode){
  if h1==nil{
    return h2
  }
  if h2==nil{
    return h1
  }
  var t *listNode
  if h1.val<h2.val{
    t=h1
    h1=h1.next
  }else{
    t=h2
    h2=h2.next
  }
  p:=t
  for h1!=nil&&h2!=nil{
    if h1.val<h2.val{
      if p.val!=h1.val{
        p.next=h1
        p=p.next
      }
      h1=h1.next
    }else{
       if p.val!=h2.val{
        p.next=h2
        p=p.next
      }
      h2=h2.next
    }
  }
  for h1!=nil{
    if p.val!=h1.val{
        p.next=h1
        p=p.next
      }
      h1=h1.next
  }
  for h2!=nil{
     if p.val!=h2.val{
        p.next=h2
        p=p.next
      }
      h2=h2.next
  }
  return t
}
```

**第k个全排列：**

```go
func kthPermutations(n int, k int) []int {
	res := make([]int, n)
	times, find := 0, false
	dfs(n, k, 0, res, make([]bool, n+1), &times, &find)
	return res
}

func dfs(n, k int, t int, res []int, visited []bool, times *int, find *bool) {
	if *find {
		return
	}
	if t == n {
		*times += 1
		if *times == k {
			*find = true
		}
		return
	}
	for i := 1; i <= n; i++ {
		if *find {
			return
		}
		if visited[i] {
			continue
		}
		visited[i] = true
		res[t] = i
		dfs(n, k, t+1, res, visited, times, find)
		visited[i] = false
	}
}
```

### 20230720 百度二面（过）

- 谈谈对go语言的理解，和java比较
- go语言面向对象
- go语言的并发、协程，底层原理
- 项目，项目架构、难点，抠细节。

**一个二维有序数组，判断某个数是否在这个二维有序数组中**

```go
func findTarget(matrix [][]int, target int) bool {
	if len(matrix) == 0 {
		return false
	}
	m, n := len(matrix), len(matrix[0])
	i, j := 0, n-1
	for i < m && j >= 0 {
		if matrix[i][j] == target {
			return true
		}

		if matrix[i][j] > target {
			j--
		} else {
			i++
		}
	}
	return false
}
```



## 迅雷

### 20230714 迅雷一面（过）

- redis异地多活，多写同一个key方案？
- MySQL分表原则。
- 为啥不能使用外键，外键的坑有哪些？

### 20230718 迅雷二面（挂）

- 设计一个100亿级别的用户打卡系统，找出前排名前1w的用户
- 项目难点以及怎么解决的？
- 对于未来的规划？

## 滴滴

### 20230715 滴滴一面（过）

- Golang判空怎么判空，判空的坑？

- new 和make的区别，内存分配怎么分配？new用于所有对象，make限制了slice、map、channel，new内存分配都在堆上，make有可能在栈上。

- defer的作用域

- 切片和数组区别，函数传递是值传递还是引用传递？

- 限流算法有哪些？怎么实现一个限流器？分布式限流器？

  >**本地限流器：**
  >
  >```go
  >package rateLimit
  >
  >import (
  >	"sync"
  >	"time"
  >)
  >
  >// RateLimiter 限流接口
  >type RateLimiter interface {
  >	// Allow 是否运行本次请求
  >	Allow() bool
  >}
  >
  >// NewLeakyRater 漏桶算法限流实现
  >func NewLeakyRater(rate, capacity int64) RateLimiter {
  >	return &leakyBucket{
  >		rate:       rate,
  >		capacity:   capacity,
  >		lastLeakMs: time.Now().UnixNano() / 1e6,
  >		mu:         &sync.Mutex{},
  >	}
  >}
  >
  >// NewTokenRater 令牌桶算法限流实现
  >func NewTokenRater(rate, capacity int64) RateLimiter {
  >	return &tokenBucket{
  >		rate:       rate,
  >		capacity:   capacity,
  >		lastFillMs: time.Now().UnixNano() / 1e6,
  >		mu:         &sync.Mutex{},
  >	}
  >}
  >
  >type leakyBucket struct {
  >	rate       int64       // 每s能够处理的请求个数
  >	capacity   int64       // 最多能够容纳的请求数量
  >	water      int64       // 当前处理的请求数量
  >	lastLeakMs int64       // 上次泄漏的时间戳（毫秒）
  >	mu         *sync.Mutex // 互斥锁，保证线程安全
  >}
  >
  >func (l *leakyBucket) Allow() bool {
  >	l.mu.Lock()         // 加锁
  >	defer l.mu.Unlock() // 函数结束时解锁
  >
  >	nowMs := time.Now().UnixNano() / 1e6              // 获取当前时间戳（毫秒）
  >	leakNum := (nowMs - l.lastLeakMs) * l.rate / 1000 // 计算从上次泄漏到现在泄漏的水量
  >	l.water -= leakNum                                // 更新水量
  >	l.lastLeakMs = nowMs                              // 更新上次泄漏时间
  >
  >	if l.water < 0 { // 如果水量小于0，将水量设置为0
  >		l.water = 0
  >	}
  >
  >	if l.water < l.capacity { // 判断是否允许新的请求
  >		l.water++
  >		return true
  >	}
  >
  >	return false
  >}
  >
  >type tokenBucket struct {
  >	rate       int64       // 令牌生成速率
  >	capacity   int64       // 令牌桶容量
  >	tokens     int64       // 当前令牌数量
  >	lastFillMs int64       // 上次填充令牌的时间戳（毫秒）
  >	mu         *sync.Mutex // 互斥锁，保证线程安全
  >}
  >
  >func (t *tokenBucket) Allow() bool {
  >
  >	t.mu.Lock()         // 加锁
  >	defer t.mu.Unlock() // 函数结束时解锁
  >
  >	nowMs := time.Now().UnixNano() / 1e6              // 获取当前时间戳（毫秒）
  >	fillNum := (nowMs - t.lastFillMs) * t.rate / 1000 // 计算从上次填充到现在新增的令牌数量
  >	t.tokens += fillNum                               // 更新令牌数量
  >	t.lastFillMs = nowMs                              // 更新上次填充时间
  >
  >	if t.tokens > t.capacity { // 如果令牌数量大于容量，将令牌数量设置为容量
  >		t.tokens = t.capacity
  >	}
  >
  >	if t.tokens > 0 { // 判断是否允许新的请求
  >		t.tokens--
  >		return true
  >	}
  >
  >	return false
  >}
  >```
  >
  >**分布式限流器：**
  >
  >```lua
  >-- 漏桶算法
  >-- leaky_bucket.lua
  >local key = KEYS[1] -- Redis key
  >local rate = tonumber(ARGV[1]) -- 漏桶处理速率
  >local capacity = tonumber(ARGV[2]) -- 漏桶容量
  >local now_ms = tonumber(ARGV[3]) -- 当前时间戳（毫秒）
  >
  >-- 从Redis中获取漏桶的当前水量和上次泄漏时间
  >local leaky_bucket = redis.call('HMGET', key, 'water', 'last_leak_ms')
  >local water = tonumber(leaky_bucket[1])
  >local last_leak_ms = tonumber(leaky_bucket[2])
  >
  >-- 计算从上次泄漏到现在泄漏的水量
  >local leak_num = math.floor((now_ms - last_leak_ms) * rate / 1000)
  >water = water - leak_num
  >last_leak_ms = now_ms
  >
  >-- 如果水量小于0，将水量设置为0
  >if water < 0 then
  >water = 0
  >end
  >
  >-- 判断是否允许新的请求
  >local allowed = 0
  >if water < capacity then
  >water = water + 1
  >allowed = 1
  >end
  >
  >-- 更新Redis中的漏桶状态
  >redis.call('HMSET', key, 'water', water, 'last_leak_ms', last_leak_ms)
  >redis.call('EXPIRE', key, 2 * capacity / rate)
  >
  >return allowed
  >
  >
  >-- 令牌桶算法
  >-- token_bucket.lua
  >local key = KEYS[1] -- Redis key
  >local rate = tonumber(ARGV[1]) -- 令牌生成速率
  >local capacity = tonumber(ARGV[2]) -- 令牌桶容量
  >local now_ms = tonumber(ARGV[3]) -- 当前时间戳（毫秒）
  >
  >-- 从Redis中获取令牌桶的当前令牌数量和上次填充时间
  >local token_bucket = redis.call('HMGET', key, 'tokens', 'last_fill_ms')
  >local tokens = tonumber(token_bucket[1])
  >local last_fill_ms = tonumber(token_bucket[2])
  >
  >-- 计算从上次填充到现在新增的令牌数量
  >local fill_num = math.floor((now_ms - last_fill_ms) * rate / 1000)
  >tokens = tokens + fill_num
  >last_fill_ms = now_ms
  >
  >-- 如果令牌数量大于容量，将令牌数量设置为容量
  >if tokens > capacity then
  >tokens = capacity
  >end
  >
  >-- 判断是否允许新的请求
  >local allowed = 0
  >if tokens > 0 then
  >tokens = tokens - 1
  >allowed = 1
  >end
  >
  >-- 更新Redis中的令牌桶状态
  >redis.call('HMSET', key, 'tokens', tokens, 'last_fill_ms', last_fill_ms)
  >redis.call('EXPIRE', key, 2 * capacity / rate)
  >
  >return allowed		

**全排列：**

```go
// nums不重复，给出全排列
func dfs(nums []int,t int,tmp []int,visited []bool,res *[][]int){
  if t==len(nums){
    data:=make([]int,0,len(tmp))
    for i:=0;i<len(tmp);i++{
      data=append(data,tmp[i])
    }
    *res=append(*res,data)
    return
  }
  
  for i:=0;i<len(nums);i++{
      if visited[i]{
          continue
      }
    	tmp[t]=nums[i]
    	visited[i]=true
    	dfs(nums,t+1,visited,tmp,res)
    	visited[i]=false
  }
}
```

**岛屿问题：**

```go
func countGrid(grids [][]int)int{
  res:=0
  m,n:=len(grids),len(grids[0])
  for i:=0;i<m;i++{
    for j:=0;j<n;j++{
      if grids[i][j]==1{
        res++
        gridDfs(grids,m,n,i,j)
        // gridBfs(grids,m,n,i,j)
      }
    }
  }
  return res
}

// gridDfs 感染，深度优先搜索
func gridDfs(grids [][]int,m,n,i,j int){
  if i<0||i>=m||j<0||j>=n||grids[i][j]=0{
    	return 
  }
  grids[i][j]=0
  gridDfs(girds,m,n,i+1,j)
  gridDfs(girds,m,n,i-1,j)
  gridDfs(girds,m,n,i,j-1)
  gridDfs(girds,m,n,i,j+1)
}

// gridBfs 感染，广度优先搜索
func gridBfs(grids [][]int, m, n int, i, j int) {
	dx := [4]int{-1, 0, 1, 0}
	dy := [4]int{0, 1, 0, -1}
	q := newQueue(m * n)
	q.push(&pair{i, j})
	for !q.isEmpty() {
		t := q.pop()
		for k := 0; k < 4; k++ {
			// 上下左右四个方向寻找
			x, y := t.x+dx[k], t.y+dy[k] // 当前位置的下一个位置
			if x >= 0 && x < m && y >= 0 && y < n && grids[x][y] == 1 {
				q.push(&pair{x, y})
				grids[x][y] = 0
			}
		}
	}
}

type pair struct {
	x int
	y int
}

type queue struct {
	elements []*pair
	begin    int
	end      int
}

func newQueue(n int) *queue {
	return &queue{
		elements: make([]*pair, n),
		begin:    0,
		end:      -1,
	}
}

func (q *queue) push(p *pair) {
	q.end += 1
	q.elements[q.end] = p
}

func (q *queue) pop() *pair {
	res := q.elements[q.begin]
	q.elements[q.begin] = nil
	q.begin += 1
	return res
}

func (q *queue) isEmpty() bool {
	return q.end < q.begin
}
```

### 20230715 滴滴二面（挂）

- redis分布式锁的坑？锁过期，任务还没完成该怎么办？锁定时续期？
- redis怎么实现一个可重入分布式锁？

> redis的hash+lua脚本
>
> **加锁：**
>
> ```lua
> -- key:hash的key，一般是业务的锁
> -- expireTime: 过期时间
> -- requestId:本次请求的唯一ID，可以理解为traceID，全局唯一
> 
> -- TryGetLock
> local function TryGetLock(key, requestId, expireTime)
>  if redis.call('EXISTS', key) == 0 then
>      -- 锁不存在，尝试获取锁
>      redis.call('HSET', key, requestId, 1)
>      redis.call('PEXPIRE', key, expireTime)
>      return {1, expireTime} -- initialize
>  else
>      -- 锁存在，检查是否是同一个请求ID
>      if redis.call('HEXISTS', key, requestId) == 1 then
>          -- 是同一个请求ID，增加计数
>          redis.call('HINCRBY', key, requestId, 1)
>          redis.call('PEXPIRE', key, expireTime)
>          return {0, redis.call('PTTL', key)} -- success
>      else
>          -- 不是同一个请求ID，获取锁失败
>          return {-1, redis.call('PTTL', key)} -- failed
>      end
>  end
> end
> ```
>
> **解锁：**
>
> ```lua
> -- key:hash的key，一般是业务的锁
> -- requestId:本次请求的唯一ID，可以理解为traceID，全局唯一
> -- expireTime: 过期时间
> 
> -- TryUnLock
> local function TryUnLock(key, requestId, expireTime)
>  if redis.call('EXISTS', key) == 0 then
>      -- 锁不存在，释放锁成功
>      return {0, 0} -- success
>  else
>      -- 锁存在，检查是否是同一个请求ID
>      if redis.call('HEXISTS', key, requestId) == 1 then
>          local cnt = redis.call('HGET', key, requestId)
>          if tonumber(cnt) == 1 then
>              -- 计数为1，删除锁
>              redis.call('HDEL', key, requestId)
>              return {0, 0} -- success
>          else
>              -- 是同一个请求ID，减少计数
>              redis.call('HINCRBY', key, requestId, -1)
>              -- 给锁续期
>              redis.call('PEXPIRE', key, expireTime)
>              return {0, redis.call('PTTL', key)} -- success
>          end
>      else
>          -- 不是同一个请求ID，释放锁失败
>          return {-1, redis.call('PTTL', key)} -- failed
>      end
>  end
> end
> ```
>
> 

- 怎么提供个分布式的redis对外使用？proxy、redis自适应hash、客户端hash
- 当MySQL表中某一列的类型是varchar，但是在sql语句中使用int查询，会有什么问题？性能下降、查询结果不准确，索引失效

> 1.在进行函数运算的时候，mysql会进行隐式转换，比如原始数据是varchar，varchar按照某种规则有序，转换成整数后可能排序规则就变了，就没法使用索引了，只能走全表扫描
>
> 2.函数运算本身也要时间的，这个会增加整体耗时。
>
> 3.函数转换的结果可能不准确，a123可能转成123，导致查询结果不准确

- redis的cluster是怎么实现的？meet命令，分片集群，槽位。
- varchar、char、text区别？如何选用哪种数据结构？varcha最大能存储的字符数，能全部存储数据吗？

> 1. char:定长字符串，性能更好，但可能会浪费存储空间
> 2. varchar :变长字符，最大存储字符长度是(1<<16)-1,更节省空间，性能稍差。
> 3. text：文本，能够存储的长度最长，但是性能更差。

- 快照读和当前读，怎么实现快照读和当前读？多版本并发控制？

  > InnoDB存储引擎通过多版本并发控制（MVCC）实现了高并发性能和事务隔离。以下是InnoDB实现MVCC的具体细节：
  >
  > 1. 事务版本号（Transaction ID）：
  >
  > InnoDB为每个事务分配一个唯一的递增的版本号，称为事务ID。事务ID用于标识事务的先后顺序，以及在MVCC中确定数据行的可见性。
  >
  > 2. Undo日志：
  >
  > InnoDB使用Undo日志来存储数据行的旧版本。当事务对数据行进行修改时，InnoDB会将修改前的数据行版本写入Undo日志。Undo日志分为两种：Insert Undo和Update Undo。Insert Undo用于存储新插入数据行的旧版本，Update Undo用于存储更新数据行的旧版本。
  >
  > 3. Read View：
  >
  > InnoDB为每个事务创建一个Read View，用于确定数据行的可见性。Read View包含以下信息：
  >
  > - 事务的版本号（即快照版本号）。
  > - 当前活跃的事务列表（即在Read View创建时尚未提交的事务）。
  >
  > Read View用于判断数据行的某个版本是否对当前事务可见。具体规则如下：
  >
  > - 如果数据行的版本号小于等于Read View的版本号，并且不属于活跃事务列表，则该数据行对当前事务可见。
  > - 如果数据行的版本号大于Read View的版本号，或者属于活跃事务列表，则该数据行对当前事务不可见，需要查找其旧版本。
  >
  > 1. 数据行结构：
  >
  > InnoDB的数据行包含以下与MVCC相关的系统列：
  >
  > - DB_TRX_ID：表示最后修改数据行的事务ID。
  > - DB_ROLL_PTR：表示指向数据行的上一个版本（即Undo日志）的指针。
  >
  > 2. 数据行可见性判断：
  >
  > 当事务需要读取数据行时，InnoDB会根据Read View和数据行的系统列判断数据行的可见性。具体步骤如下：
  >
  > - 检查数据行的DB_TRX_ID，如果小于等于Read View的版本号，并且不属于活跃事务列表，则该数据行对当前事务可见，可以直接返回。
  > - 如果数据行的DB_TRX_ID大于Read View的版本号，或者属于活跃事务列表，则该数据行对当前事务不可见，需要查找其旧版本。此时，通过DB_ROLL_PTR找到对应的Undo日志，并递归判断Undo日志中的数据行版本是否可见。
  >
  > 3. 数据行修改：
  >
  > 当事务需要修改数据行时，InnoDB会执行以下操作：
  >
  > - 为修改后的数据行分配一个新的事务ID（即当前事务的ID）。
  > - 将修改前的数据行版本写入Undo日志，并更新数据行的DB_ROLL_PTR指向Undo日志。
  > - 如果当前事务是第一个修改数据行的事务，还需要将数据行的DB_TRX_ID更新为当前事务的ID。
  >
  > 通过上述机制，InnoDB实现了MVCC，支持多个事务并发访问数据，同时保证了事务隔离性。需要注意的是，InnoDB的MVCC实现与事务隔离级别有关。在不同的隔离级别下，Read View的创建时机和数据行可见性判断规则可能会有所不同。
  
- 快照读和当前读
> InnoDB通过在每个数据行中添加额外的系统列（如DB_TRX_ID和DB_ROLL_PTR）来维护数据的多个版本。
>
> 1. 快照读（Snapshot Read）：
>
> 在InnoDB中，快照读主要用于实现可重复读（Repeatable Read）隔离级别。当事务开始时，InnoDB会为该事务分配一个唯一的事务ID，并记录当前的系统版本号作为快照版本号。
>
> 当事务需要读取数据时，InnoDB会遍历数据行的版本链表，找到版本号小于等于快照版本号的最新版本。具体步骤如下：
>
> - 检查数据行的DB_TRX_ID，如果小于等于快照版本号，说明该行数据在事务开始前已经存在，可以直接返回。
> - 如果数据行的DB_TRX_ID大于快照版本号，说明该行数据是在事务开始后被其他事务插入或更新的。此时，需要通过DB_ROLL_PTR找到该行数据的上一个版本。
> - 递归检查上一个版本的DB_TRX_ID，直到找到一个版本号小于等于快照版本号的数据行，然后返回该行数据。
>
> 2. 当前读（Current Read）：
>
> 在InnoDB中，当前读主要用于实现读已提交（Read Committed）隔离级别。当事务需要读取数据时，InnoDB会直接返回数据行的最新版本。具体步骤如下：
>
> - 检查数据行的DB_TRX_ID，如果小于等于当前事务ID，说明该行数据在当前事务开始前已经存在，可以直接返回。
> - 如果数据行的DB_TRX_ID大于当前事务ID，说明该行数据是在当前事务开始后被其他事务插入或更新的。此时，需要通过DB_ROLL_PTR找到该行数据的上一个版本。
> - 递归检查上一个版本的DB_TRX_ID，直到找到一个版本号小于等于当前事务ID的数据行，然后返回该行数据。
>
> 需要注意的是，当前读可能导致不可重复读和幻读等问题。为了解决这些问题，InnoDB还提供了行锁和间隙锁等锁机制来实现更高的隔离级别。

- cap理论，分区容错性必须得保证，可用性和一致性取舍，当为了高可用牺牲部分一致性的时候，有哪些手段可以尽量保证数据一致性？

> 1. 数据对账
> 1. 读修复，自修复能力。
> 1. 定时巡检，数据不一致上报。
> 1. 异步消息队列，消费对账。

- go语言判空的坑

**两个协程交替打印0和1，一个只打印0，一个只打印1:**

```go
func printDigit() {
	var wg sync.WaitGroup
	wg.Add(2)
	ch1, ch2 := make(chan struct{}), make(chan struct{})
	const printNum = 100
	go func() {
		defer wg.Done()
		for i := 0; i < printNum; i++ {
			<-ch1
			fmt.Println("goroutinue1:", 0)
			ch2 <- struct{}{}
		}
	}()

	go func() {
		defer wg.Done()
		for i := 0; i < printNum; i++ {
			<-ch2
			fmt.Println("goroutinue2:", 1)
			if i != printNum-1 {// 因为在外面ch1先塞了一次，所以这里要少塞一次
				ch1 <- struct{}{} 
			}
		}
	}()
	ch1 <- struct{}{}
	wg.Wait()
}

```

**最长回文子串：**

```go
func palindromeSubString(str string) string{
  n:=len(str)
  dp:=make([][]bool,n)
  for i:=0;i<n;i++{
    dp[i]=make([]bool,n)
    dp[i][i]=true
    if i<n-1{
      dp[i][i+1]=str[i]==str[i+1]
    }
  }
  maxLen,beginIndex:=1,-1
  for l:=3;l<=n;l++{
    for i:=0;i+l<=n;i++{
      dp[i][i+l-1]=dp[i+1][i+l-2]&&(str[i]==str[i+l-1])
      if dp[i][i+l-1]{
        maxLen=l
        beginIndex=i
      }
    }
  }
  return str[beginIndex:maxLen+beginIndex]
}
```



## 莉莉丝

### 20230721 莉莉丝一面（过）

- 聊项目难点
- 聚簇索引和非聚簇索引
- redis的持久化方式？
- redis挂了怎么办？

## 小红书（HR挂）

### 20230727 小红书一面（过）

- mysql的事务，为什么用到事务？
- java的jvm以及垃圾回收机制
- java的hashmap和concurrent hashmap
- 项目难点，负责模块
- mysql的索引，b+树
- mysql的事务原子性怎么保证的？
- 两个事务同时更新一条数据会发生什么？

> 会阻塞，因为更新同一行数据自动使用排它锁

- 二叉树最大路径和

> ```go
> func getMaxPath(root *Tree) int{
> if root==nil{
>  return 0
> }
> result:=root.val
> postOrder(root,&result)
> return result
> }
> 
> func postOrder(root *Tree,result *int) int{
> if root==nil{
>  return 0
> }
> l,r:=postOrder(root.left,result),postOrder(root.right,result)
> mx:=max(l,r)
> mx=max(mx,l+r)
> mx=max(mx,0)
> *result=max(*result,mx+root.val)
> return max(max(l,r),0)+root.val
> }
> 
> 
> func max(a,b int) int{
> if a<b{
>  return b
> }
> return a
> }
> ```
>

### 20230801 小红书二面（过）

- 项目大概30min
- 写一个线上可以使用的localCache，使用lru作为淘汰算法

```go
package main

import (
	"errors"
	"fmt"
	"hash/fnv"
	"log"
	"sync"
	"sync/atomic"
)

var (
	errEmptyCache = errors.New("not initialization")
	errInvalidKey = errors.New("invalid key")
	errNotExist   = errors.New("not existed key")
)

func main() {
	cache, err := NewLocalCache(5, 3)
	if err != nil {
		log.Fatalf("NewLocalCache failed:%+v", err)
	}
	for i := 0; i < 18; i++ {
		key := fmt.Sprintf("key%d", i+1)
		val := []byte(fmt.Sprintf("val%d", i+1))
		if err = cache.Set(key, val); err != nil {
			log.Fatalf("set cache failed;key:%s,val:%s failed:%+v", key, string(val), err)
		}
	}
	fmt.Println(*cache)
	fmt.Println(cache.totalKeyNum)
	cache.Iterator()
	if _, err = cache.Get("key3"); err != nil {
		fmt.Println(err)
	}
	cache.Iterator()

}

type LocalCache struct {
	totalKeyNum int64
	shards      []*lru
}

func NewLocalCache(eachShardSize int, shardNum int) (*LocalCache, error) {
	if eachShardSize == 0 || shardNum == 0 {
		return nil, errEmptyCache
	}
	dataList := make([]*lru, shardNum)
	for i := 0; i < len(dataList); i++ {
		dataList[i] = newLRU(eachShardSize)
	}
	return &LocalCache{
		shards: dataList,
	}, nil

}

func (l *LocalCache) Get(key string) ([]byte, error) {
	if len(key) == 0 {
		return nil, errInvalidKey
	}
	index := hash(key) % (len(l.shards))
	l.shards[index].mu.Lock()
	defer l.shards[index].mu.Unlock()
	node, ok := l.shards[index].dict[key]
	if !ok {
		return nil, errNotExist
	}
	l.readPreheat(node, index)
	return node.val, nil
}

func (l *LocalCache) Set(key string, val []byte) error {
	if len(l.shards) == 0 {
		return errEmptyCache
	}
	if len(key) == 0 {
		return errInvalidKey
	}
	index := hash(key) % (len(l.shards))
	l.shards[index].mu.Lock()
	defer l.shards[index].mu.Unlock()
	node, ok := l.shards[index].dict[key]
	if ok {
		node.val = val
		l.readPreheat(node, index)
		return nil
	}
	newNode := &listNode{
		val:  val,
		next: l.shards[index].head.next,
		pre:  l.shards[index].head,
		key:  key,
	}
	l.shards[index].head.next.pre = newNode
	l.shards[index].head.next = newNode
	if l.shards[index].shardKeyNum == l.shards[index].size {
		deleteNode := l.shards[index].tail.pre
		l.shards[index].tail.pre = deleteNode.pre
		deleteNode.pre.next = l.shards[index].tail
		delete(l.shards[index].dict, deleteNode.key)
		atomic.AddInt64(&l.totalKeyNum, -1)
		l.shards[index].shardKeyNum -= 1
	}
	l.shards[index].dict[key] = newNode
	atomic.AddInt64(&l.totalKeyNum, 1)
	l.shards[index].shardKeyNum += 1
	return nil
}

func (l *LocalCache) Iterator() {
	for i := 0; i < len(l.shards); i++ {
		fmt.Printf("shard%d  begin\n", i+1)
		l.shards[i].iterator()
		fmt.Printf("shard%d end~ \n ", i+1)
		fmt.Println()
	}
}

func (l *LocalCache) readPreheat(node *listNode, index int) {
	node.pre.next = node.next
	node.next.pre = node.pre
	node.next = l.shards[index].head.next
	l.shards[index].head.next.pre = node
	node.pre = l.shards[index].head
	l.shards[index].head.next = node
}

func (l *lru) iterator() {
	p := l.head
	for p.next != l.tail {
		p = p.next
		fmt.Printf("kev:%s,val:%s\n", p.key, p.val)
	}
}

func newLRU(eachShardSize int) *lru {
	head := &listNode{}
	tail := &listNode{}
	head.next = tail
	tail.pre = head
	return &lru{
		size: eachShardSize,
		head: head,
		tail: tail,
		mu:   sync.Mutex{},
		dict: make(map[string]*listNode, eachShardSize),
	}
}

type lru struct {
	mu          sync.Mutex
	size        int
	shardKeyNum int
	head, tail  *listNode
	dict        map[string]*listNode
}

type listNode struct {
	key       string
	val       []byte
	pre, next *listNode
}

func hash(key string) int {
	h := fnv.New32a()
	_, _ = h.Write([]byte(key))
	return int(h.Sum32())
}

```

### 29230808 小红书三面（过）

- 设计的这个分表hash结构具有通用性吗
- 为啥最初选用redis作为db使用
- 项目中有哪些不稳定的地方待解决，怎么解决？
- 对未来的规划和期待

## 米哈游

### 20230801 米哈游一面（过）

- 项目30min
- 没有初始化的map和slice赋值会panic，recover能捕获吗？可以捕获
- 并发读写slice和map会panic吗？recover能捕获吗？会panic不能捕获
- 如果一个channel没有初始化，读写数据会有什么问题？读写不会阻塞，也不会panic
- 如果一个channel已经close，继续读写数据会有什么问题？如果panic能捕获异常吗？读不会有问题，写会panic且不能被捕获
- 子数组的最大乘积

> ```go
> func maxProduct1(nums []float64) float64 {
> 	if len(nums) == 0 {
> 		return 0
> 	}
> 	dp1 := make([]float64, len(nums))
> 	dp2 := make([]float64, len(nums))
> 	dp1[1], dp2[1] = nums[0], nums[0]
> 	res := dp1[1]
> 	for i := 1; i < len(nums); i++ {
> 		dp1[i] = max(nums[i], max(dp1[i-1]*nums[i], dp2[i-1]*nums[i]))
> 		dp2[i] = min(nums[i], min(dp1[i-1]*nums[i], dp2[i-1]*nums[i]))
> 		res = max(res, dp1[i])
> 	}
> 	return res
> }
> 
> func maxProduct2(nums []float64) float64 {
> 	if len(nums) == 0 {
> 		return 0
> 	}
> 	dp1, dp2 := nums[0], nums[0]
> 	res := dp1
> 	for i := 1; i < len(nums); i++ {
> 		tmpDp1 := dp1
> 		dp1 = max(nums[i], max(dp1*nums[i], dp2*nums[i]))
> 		dp2 = min(nums[i], min(tmpDp1*nums[i], dp2*nums[i]))
> 		res = max(res, dp1)
> 	}
> 	return res
> }
> 
> func max(a, b float64) float64 {
> 	if a < b {
> 		return b
> 	}
> 	return a
> }
> 
> func min(a, b float64) float64 {
> 	if a < b {
> 		return a
> 	}
> 	return b
> }
> 
> ```

### 20230808 米哈游二面（挂）

- 聊项目30min
- 消息流量怎么解决？消息的包体会很大
- 消息空洞怎么解决？
- 消息的删除，只删除自己的消息多端同步？

## B站（offer)

### 20230802 B站一面（过）

- 主要聊项目，项目难点，表分裂
- redis的cluster怎么实现的，如果扩容结点，redis该怎么做
- redis的hash扩容该怎么做，是渐进式扩容吗？

### 20230804 B站二面（过）

- 聊项目30min

- 怎么保证接口幂等

```shell
1.redis set nx
2.token机制+redis
3.关系型数据库+唯一索引
4.防重复表
5.分布式锁
```

- 快排
- 为啥用hash结构，其它结构不行吗？只用hash有啥问题？

### 20230809 B站三面（过）

- 说一下你技术上最有成就感的一个事
- 非技术上最有成就感的一个事
- 长连接优势及好处
- 如果消息通道挂了，该怎么办？，有什么降级策略？

## 鹰角

### 20230804 鹰角一面（挂）

- 项目，怎么分表，怎么拆分？
- 如果要合并怎么办，子表空洞？子表合并？
- 判断回文链表

> ```go
> package main
> 
> import "fmt"
> 
> func main() {
> 	h1 := buildListNode([]int{1, 2, 3, 4, 5})    // false
> 	h2 := buildListNode([]int{1, 2, 3, 2, 1})    // true
> 	h3 := buildListNode([]int{1, 2, 3, 3, 2, 5}) // false
> 	h4 := buildListNode([]int{1, 2, 3, 3, 2, 1}) // true
> 	h5 := buildListNode([]int{1, 2})             // false
> 	h6 := buildListNode([]int{1})                // true
> 	h7 := buildListNode([]int{1, 2, 2, 1})       // true
> 	h8 := buildListNode([]int{1, 1})             // true
> 	fmt.Println(isPalindrome(h1))
> 	fmt.Println(isPalindrome(h2))
> 	fmt.Println(isPalindrome(h3))
> 	fmt.Println(isPalindrome(h4))
> 	fmt.Println(isPalindrome(h5))
> 	fmt.Println(isPalindrome(h6))
> 	fmt.Println(isPalindrome(h7))
> 	fmt.Println(isPalindrome(h8))
> }
> 
> func buildListNode(nums []int) *ListNode {
> 	h := &ListNode{}
> 	p := h
> 	for _, num := range nums {
> 		p.Next = &ListNode{Val: num}
> 		p = p.Next
> 	}
> 	return h.Next
> }
> 
> func isPalindrome(head *ListNode) bool {
> 	if head == nil || head.Next == nil {
> 		return true
> 	}
> 	l1, l2 := findMedium(head)
> 	// head = reverse(head, l1)
> 	head = reverse1(head, l1)
> 	for l2 != nil && head != nil {
> 		if l2.Val != head.Val {
> 			return false
> 		}
> 		l2 = l2.Next
> 		head = head.Next
> 	}
> 	if l2 != nil || head != nil {
> 		return false
> 	}
> 	return true
> }
> 
> func reverse1(begin, end *ListNode) *ListNode {
> 	if begin == nil || end == nil || begin == end {
> 		return begin
> 	}
> 	h := &ListNode{}
> 	for begin != end {
> 		next := begin.Next
> 		begin.Next = h.Next
> 		h.Next = begin
> 		begin = next
> 	}
> 	end.Next = h.Next
> 	h.Next = end
> 	return h.Next
> }
> func reverse2(begin, end *ListNode) *ListNode {
> 	if begin == end {
> 		return begin
> 	}
> 	var p *ListNode
> 	for begin != end {
> 		next := begin.Next
> 		begin.Next = p
> 		p = begin
> 		begin = next
> 	}
> 	end.Next = p
> 	return end
> }
> 
> func reverse3(begin *ListNode, end *ListNode) *ListNode {
> 	if begin == nil || begin == end {
> 		return begin
> 	}
> 	next := reverse1(begin.Next, end)
> 	begin.Next.Next = begin
> 	begin.Next = nil
> 	return next
> }
> 
> func findMedium(head *ListNode) (*ListNode, *ListNode) {
> 	p := &ListNode{
> 		Next: head,
> 	}
> 	for head != nil && head.Next != nil {
> 		head = head.Next.Next
> 		p = p.Next
> 	}
> 	if head == nil {
> 		l2 := p.Next
> 		p.Next = nil
> 		return p, l2
> 	}
> 	l2 := p.Next.Next
> 	p.Next = nil
> 	return p, l2
> }
> 
> type ListNode struct {
> 	Val  int
> 	Next *ListNode
> }
> ```
>
> 

## 蚂蚁金服

### 20230814 蚂蚁金服一面（挂）

- 三数之和，无重复结果。

```go
func threeSum(nums []int) [][]int {
	if len(nums) < 3 {
		return nil
	}
	sort.Ints(nums)
	var res [][]int
	for i := 0; i < len(nums)-2; i++ {
		if nums[i] > 0 {
			break
		}
		if i > 0 && nums[i] == nums[i-1] {
			continue
		}
		left, right := i+1, len(nums)-1
		target := -nums[i]
		for left < right {
			if nums[left]+nums[right] == target {
				res = append(res, []int{nums[i], nums[left], nums[right]})
				l, r := nums[left], nums[right]
				for left < right && nums[left] == l {
					left++
				}
				for left < right && nums[right] == r {
					right--
				}
			} else if nums[left]+nums[right] < target {
				left++
			} else {
				right--
			}
		}
	}
	return res
}
```



- 单词数组反转，去掉多余空格

```go
func reverseWords(words string) string {
	left, right := 0, len(words)-1
	for left <= right && !isLetter(words[left]) {
		left++
	}
	for left <= right && !isLetter(words[right]) {
		right--
	}
	if left > right {
		return ""
	}
	var sb strings.Builder
	words = reverseStr(words, left, right)
	i := 0
	for i < len(words) {
		j := i
		for j < len(words) && isLetter(words[j]) {
			j++
		}
		bs := reverseStr(words, i, j-1)
		sb.WriteString(bs)
		if j < len(words) {
			sb.WriteString(" ")
		}
		for j < len(words) && words[j] == ' ' {
			j++
		}
		i = j
	}
	return sb.String()
}

func reverseStr(s string, i, j int) string {
	if i > j {
		return ""
	}
	res := []byte(s[i : j+1])
	i, j = 0, len(res)-1
	for i < j {
		res[i], res[j] = res[j], res[i]
		i++
		j--
	}
	return string(res)
}

func isLetter(b byte) bool {
	return b != ' '
}
```



- 阻塞写入该怎么办，排队，聚合写入，异步。

## 字节跳动

### 20230821 字节跳动一面（挂）
- 聊项目，扣细节，底层关系链怎么设计，消息怎么分发。
- 一个好的系统应该是怎么样的？
- 设计一个cache，带过期时间自动淘汰并且当数据满了的时候会使用lru算法淘汰内存

> ```go
> package main
> 
> import (
> 	"fmt"
> 	"sync"
> 	"time"
> )
> 
> // 国际化短视频
> // tikto
> 
> /**
> 设计一个对象cache, 他支持下列两个基本操作:
> set(id, object), 根据id设置对象;
> get(id): 根据id得到一个对象;
> 同时它有下面几个性质:
> 1: x秒自动过期, 如果cache内的对象, x秒内没有被get或者set过, 则会自动过期;
> 2: 对象数限制, 该cache可以设置一个n, 表示cache最多能存储的对象数;
> 3: LRU置换, 当进行set操作时, 如果此时cache内对象数已经到达了n个, 则cache自动将最久未被使用过的那个对象剔除, 腾出空间放置新对象;
> 请你设计这样一个cache;
> */
> 
> func main() {
> 	c := New(20, 10)
> 	c.Set("1", 10)
> 	fmt.Println(c.Get("1"))
> }
> 
> type Cache struct {
> 	dict           map[string]*listNode
> 	head, tail     *listNode
> 	capacity       int
> 	expireDuration int64
> 	mu             *sync.Mutex
> }
> 
> func New(n int, x int64) Cache {
> 	head, tail := &listNode{}, &listNode{}
> 	head.right = tail
> 	tail.left = head
> 	cache := Cache{
> 		dict:           make(map[string]*listNode, n),
> 		head:           head,
> 		tail:           tail,
> 		capacity:       n,
> 		expireDuration: x,
> 		mu:             &sync.Mutex{},
> 	}
> 	go func() {
> 		for {
> 			time.Sleep(200 * time.Millisecond)
> 			cache.mu.Lock()
> 			const scanUmm = 100
> 			i := 0
> 			for k, v := range cache.dict {
> 				i++
> 				if i == scanUmm {
> 					break
> 				}
> 				if v.expireTimeStamp < int64(time.Now().Second()) {
> 					delete(cache.dict, k)
> 					v.left.right = v.right
> 					v.right.left = v.left
> 				}
> 			}
> 			cache.mu.Unlock()
> 		}
> 	}()
> 	return cache
> }
> 
> func (c *Cache) Set(key string, val int) {
> 	c.mu.Lock()
> 	defer c.mu.Unlock()
> 	node, ok := c.dict[key]
> 	if ok {
> 		node.val = val
> 		node.expireTimeStamp = c.expireDuration + int64(time.Now().Second())
> 
> 		node.left.right = node.right
> 		node.right.left = node.left
> 
> 		node.right = c.head.right
> 		c.head.right.left = node
> 		node.left = c.head
> 		c.head.right = node
> 		return
> 	}
> 
> 	node = &listNode{
> 		key:             key,
> 		val:             val,
> 		expireTimeStamp: c.expireDuration + int64(time.Now().Second()),
> 	}
> 
> 	if c.capacity == len(c.dict) {
> 		deletedNode := c.tail.left
> 		delete(c.dict, deletedNode.key)
> 		deletedNode.left.right = c.tail
> 		c.tail.left = deletedNode.left
> 	}
> 	c.dict[key] = node
> 	node.right = c.head.right
> 	c.head.right.left = node
> 	node.left = c.head
> 	c.head.right = node
> }
> 
> func (c *Cache) Get(key string) int {
> 	c.mu.Lock()
> 	defer c.mu.Unlock()
> 	node, ok := c.dict[key]
> 	if !ok {
> 		return -10000
> 	}
> 
> 	if node.expireTimeStamp < int64(time.Now().Second()) {
> 		delete(c.dict, node.key)
> 		node.left.right = node.right
> 		node.right.left = node.left
> 		return -10000
> 	}
> 	node.expireTimeStamp = c.expireDuration + int64(time.Now().Second())
> 
> 	node.left.right = node.right
> 	node.right.left = node.left
> 
> 	node.right = c.head.right
> 	c.head.right.left = node
> 	node.left = c.head
> 	c.head.right = node
> 	return node.val
> }
> 
> type listNode struct {
> 	key             string
> 	val             int
> 	left, right     *listNode
> 	expireTimeStamp int64
> }
> 
> ```
>
> 

## 百度（offer)

### 20230824 百度一面（过）

- 聊项目，抠细节，30分钟
- mysql的索引、事务

- 微服务治理手段，方法

- 连续子序列最大和

  ```go
  func maxSum(nums []int) int{
    if len(nums)==0{
      return 0
    }
    s:=nums[0]
    res:=s
    for i:=1;i<len(nums);i++{
      s=max(nums[i],nums[i]+s)
      res=max(res,s)
    }
    return res
  }
  
  func max(a,b int) int{
    if a<b{
      return b
    }
    return a
  }
  ```

### 20230830 百度二面（过）

  - id 转换服务，为啥用slice而不是用map
  - 如果短时间内有大量服务进来，缓存穿透，该怎么处理？提前预热，降级丢弃，步隆过滤器，流量探测异常熔断，合并排队。
  - 消息通道是怎么做的？消息分级，消息精简。

### 20230906 百度三面（过）

- 最优挑战性的一个技术优化
- 和客户端合作的一个技术优化，最后优化的成果是什么样的？对于百度ai的看法
- 自己最大的优点是什么，自己最大的不足是什么？

## 高德

### 20230829 高德一面（挂）

- mysql的索引，索引优化，哪些字段不适合建立索引？
- mysql支持事务消息吗？怎么做的？
- redis的ziplist，怎么实现的？
- kafka消息积压怎么处理？增大分区数、增大消费者数量、降级处理，丢弃消息，并发消费。kafka的一些常见概念
- kafka为啥快，mysql分表问题，如果以name分表，但是以address为查询条件，该怎么做？全局索引，mysql的全局索引
- 合并两个有序单链表

## 字节跳动

### 20230831 字节跳动一面（挂）

- kafka的八股文，怎么保证数据不丢、怎么保证解决消息积压问题。
- kafka的realance，kafka的高性能，高吞吐量。
- 分表的策略怎么实现，如何解决数据一致性。
- redis实现分布式可重入锁怎么实现？
- 有序数组和为某个target的对数？

## 快手（offer)

### 20230831 快手一面（过）

- mysql的事务、索引等，具体例子分析索引使用情况。
- mysql的间隙锁，怎么做的？间隙锁能解解决幻读吗？
- 线上事故排查，cpu飙高怎么处理，解决方案和思路。
- 怎么解决大key和热key问题？分库分表，构建缓存？缓存一致性
- 二分查找

### 20230904 快手二面（过）

- 项目，怎么解决大key和热key问题
- 10亿个map<uint64,uint64>键值对，不考虑内存空洞占用多少空间，考虑内存空洞呢？如果考虑内存空洞呢？量级是怎么样的？
- lru算法

### 20230908 快手三面（过）

- 直播场景怎么实现高并发推送消息
- im怎么实现的，如何应对策略。
- 给定一个固定长度的数组，实现一个环形队列，并且实现add,pop两个方法。

```go
type queue struct{
    b int
    e int
    currentSize int
    nums []int
}
const invalid=-1
func (q *queue) pop() int{
    if q.currentSize==0{
        return  invalid
    }
    res:=q.nums[q.b]
    q.b=(q.b+1)%len(q.nums)
    q.currentSize-=1
    return res
}

// 1 2 3 4 5
// 0 2 3 4 5
// 6 2 3 4 5
func (q *queue) add(num int) int{
    if q.currentSize>=len(q.nums){
        return invalid
    }
    q.e=(q.e+1)%len(q.nums)
    q.nums[q.e]=num
    q.currentSize+=1
    return num
}

func New(capacity int) queue{
    return queue{
        nums:make([]int,capacity),
        b:0,
        e:-1,
    }
}
```

## 滴滴（offer)

### 20230902 滴滴一面（过）

- 聊项目，分裂怎么分裂的，合并怎么合并的？
- kafka如何保证分区数据有序的？
- mysql事务的索引、事务。
- 重排链表，1 2 3 4 5 6 7 -> 1 7 2 6 3 5 4

```go
func resortListNode(head *ListNode) *ListNode {
	h := reverse(findMedium(head))
	t := head
	for h != nil && head != nil {
		next1, next2 := head.Next, h.Next
		h.Next = head.Next
		head.Next = h
		head = next1
		h = next2
	}
	return t
}

type ListNode struct {
	Val  int
	Next *ListNode
}

// 1 2 3 4 5 6 7
func buildListNode(nums []int) *ListNode {
	h := &ListNode{}
	p := h
	for i := 0; i < len(nums); i++ {
		node := &ListNode{Val: nums[i]}
		h.Next = node
		h = h.Next
	}
	return p.Next
}

func reverse(head *ListNode) *ListNode {
	var p *ListNode
	for head != nil {
		next := head.Next
		head.Next = p
		p = head
		head = next
	}
	return p
}

// 1 2 3 4 5 6 7
// 1 2 3 4
// 5 6 7
func findMedium(head *ListNode) *ListNode {
	h := head
	for head != nil && head.Next != nil {
		h = h.Next
		head = head.Next.Next
	}
	res := h.Next
	h.Next = nil
	return res
}
```



### 20230902 滴滴二面（过）

- 聊项目，怎么解决大key和热key的
- 如果发消息某台机器挂了怎么办岂不是消息丢失了？
- webSocket阻塞式和非阻塞式
- tcp的滑动窗口是干嘛的，有什么用？
- 对于未来职业规划

## 字节跳动

### 20230911 字节跳动一面（过）

- map<int,stu> 垃圾回收的时候会扫描多少个对象。map<string,[]byte)呢
- kafka怎么保证消息不重复消费
- 一致性hash算法是怎么做的？有什么好处
- 有70个硬币，A和B轮流拿，A先拿，最后一次拿走剩下全部硬币的人获胜，A有没有必胜的拿法。70%(1+7)=6
- 判断两个链表是不是相交，如果是返回相交结点。