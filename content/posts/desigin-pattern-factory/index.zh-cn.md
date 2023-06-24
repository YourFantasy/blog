---
weight: 4
title: "设计模式之工厂模式"
date: 2023-06-24T12:57:40+08:00
lastmod: 2023-06-24T14:57:40+08:00
draft: false
author: "Bard"
description: "三种工厂模式"
images: []
resources:

tags: ["desigin-patter"]
categories: ["technology"]

lightgallery: true
---

 工厂模式大致可分为
 - 简单工厂模式
 - 工厂方法模式
 - 抽象工厂模式

下面就这三种工厂模式做一下介绍并配上实现代码

## 简单工厂模式

> 简单工厂模式，也叫静态方法模式，在对象创建工厂类中定义了一个静态方法来创建对象，简单工厂设计模式让客户端（使用者）无需知道对象的具体细节就能创建出所需的产品实例，使用者可以直接使用生产出来的对象而无需关心对象是如何生产出来的。

**类图：**

![](https://md-picture-1257710623.cos.accelerate.myqcloud.com/2023/06/24/16876029307095.jpg)

**代码：**
```go
package main

import "fmt"

type Animal interface {
	eat()
	weight() int
}

type Dog struct {
}

func (d *Dog) eat() {
	fmt.Println("dog eat !")
}

func (d *Dog) weight() int {
	return 30
}

type Cat struct {
}

func (c *Cat) eat() {
	fmt.Println("cat eat!")
}

func (c *Cat) weight() int {
	return 10
}

type AnimalFactory struct {
}

func (a *AnimalFactory) newAnimal(animalType int) Animal {
	switch animalType {
	case 0:
		return &Dog{}
	case 1:
		return &Cat{}
	default:
		return nil
	}
}

func main() {
	factory := new(AnimalFactory)
	dog := factory.newAnimal(0)
	dog.eat()
	fmt.Println(dog.weight())

	cat := factory.newAnimal(1)
	cat.eat()
	fmt.Println(cat.weight())
}
```

可以看到简单工厂模式还是挺简单的，实现了将创建实例和使用实例分离，使用者无需关心实例创建过程，实现了分离解耦，无需知道被创建对象的详细信息，只需要知道该对象对应的类型映射即可。那么简单工厂模式有什么缺点呢？在生产对象的时候，根据传入的animal类型来确定创建哪个具体的动物对象，当我们增加更多的annimal种类的时候，比如增加兔子、大象等animal，随着动物种类的越来越多，newAnimal方法就会不断膨胀，并且每次动物种类发生变动的时候，都要去修改这部分代码，不符合开闭原则。

那么如何解决上述问题呢？其实也不能说解决，只能算一个编程小技巧，可以发现newAnimal方法大量的swich case，每次如何干掉这些swich case呢？在main函数中，当我们需要创建某个具体动物对象的时候，需要传入animalType字段然后调用newAnimal方法创建对象，也就是说，我们需要用到某个动物对象的时候才去创建，是一种“懒加载思想”;如果我们每次增加一个新的动物的时候，就创建该动物的实例，然后放到一个map字典中，在要用到该动物的时候，直接从map中取，不就不用维护一个newAnimal方法吗？其实就是把“懒加载思想”转化为“饿加载思想”，不管你用不用我这个对象，我这个对象既然存在，不管三七二十一，就创建一个对象实例塞到map字典里面再说。代码可以改为如下这样：

```go
package main

import "fmt"

// 饿加载，注册到map工厂
func init() {
	Register(0, &Dog{})
	Register(1, &Cat{})
}

type Animal interface {
	eat()
	weight() int
}

type Dog struct {
}

func (d *Dog) eat() {
	fmt.Println("dog eat !")
}

func (d *Dog) weight() int {
	return 30
}

type Cat struct {
}

func (c *Cat) eat() {
	fmt.Println("cat eat!")
}

func (c *Cat) weight() int {
	return 10
}

type AnimalFactory struct {
}

func Register(animalType int, animal Animal) {
	animals[animalType] = animal
}

func Get(animalType int) Animal {
	a, ok := animals[animalType]
	if !ok {
		return nil
	}
	return a
}

var animals = make(map[int]Animal) // animal type => Animal

func main() {
	dog := Get(0)
	dog.eat()
	fmt.Println(dog.weight())

	cat := Get(1)
	cat.eat()
	fmt.Println(cat.weight())
}
```

## 工厂方法模式

> 工厂方法模式也叫多态工厂模式，前面介绍了一下简单工厂模式，动物创建工厂无论什么Dog还是Cat都在同一个动物工厂生产，每次需要增加新的动物种类的时候，动物工厂都需要作出相应的改变。就好比，每次生产一个新的动物物种，都需要增加相应的配套工具，这对于系统的扩展性不是很好。工厂方法模式可以看作是对简单工厂模式的一种升级，即不同种类的动物不再在同一个动物工厂生产了，而是进行了细分，每种类型的动物都有一个专门的动物工厂进行生产，这里以汽车作为例子。

**类图：**
![](https://md-picture-1257710623.cos.accelerate.myqcloud.com/2023/06/24/16876029613580.jpg)


```go
package main

import "fmt"

// Car 汽车抽象接口，定义car的两个行为，开车和加油
type Car interface {
	drive()
	oil(cnt int)
}

// Bmw 宝马汽车
type Bmw struct {
}

func (b *Bmw) drive() {
	fmt.Println("i drive bmw!")
}

func (b *Bmw) oil(cnt int) {
	fmt.Println("bmw add ", cnt, " oil")
}

// Benz 奔驰汽车
type Benz struct {
}

func (b *Benz) drive() {
	fmt.Println("i drive benz!")
}

func (b *Benz) oil(cnt int) {
	fmt.Println("benz add ", cnt, " oil")

}

// CarFactory 汽车工厂接口，生产汽车
type CarFactory interface {
	makeCar() Car
}

// BmwFactory 宝马汽车工厂，生产宝马汽车
type BmwFactory struct {
}

func (b *BmwFactory) makeCar() Car {
	return new(Bmw)
}

// BenzFactory 奔驰汽车工厂，生产奔驰汽车
type BenzFactory struct {
}

func (b *BenzFactory) makeCar() Car {
	return new(Benz)
}

func main() {
	bmwFactory := new(BmwFactory)
	bmw := bmwFactory.makeCar()
	bmw.drive()
	bmw.oil(1)

	benzFactory := new(BenzFactory)
	benz := benzFactory.makeCar()
	benz.drive()
	benz.oil(2)
}
```

简单总结一下工厂方法模式的优缺点：

**优点：**

1.可扩展性好，当需要增加一款新的产品时（如添加奥迪汽车），无需修改抽象工厂和抽象工厂提供的接口，祝需要添加一个具体工厂和具体产品就行了，更加符合“开闭原则”，简单工厂模式则需要修改工厂类的判断逻辑，

2.符合单一职责原则：每个具体工厂类只负责生产对应的产品。简单工厂模式的工厂类还需要有一定逻辑判断

3.基于⼯⼚⻆⾊和产品⻆⾊的多态性设计是⼯⼚⽅法模式的关键。它能够使⼯⼚可以⾃主确定创建何种产品对象（该产品的工厂类只需要实现抽象工厂接口即可），⽽如何创建这个对象的细节则完全封装在具体⼯⼚内部。⼯⼚⽅法模式之所以⼜被称为多态⼯⼚模式，是因为所有的具体⼯⼚类都具有同⼀抽象⽗类。

**缺点：**

1.每次添加新的产品，都需要编写新的具体产品类，并且同时也要提供该产品对应的工厂类，当系统中产品数量表多的时候，类的个数会因此成倍增加，会在一定成都上导致系统的复杂性，并且多个类需要编译运行，会在一定程度上增加系统的开销

2.一个具体工厂类只能创建一种具体产品

 

## 抽象工厂模式

> 抽象工厂模式可以理解为生产工厂的工厂，即有一个超级工厂生产其他的工厂。马克思说过：“人是一切社会关系的总和”，一个人在社会上不可能只扮演一种角色，一个人的职业可能是程序员、也有其相应的家庭角色；同时程序员也有go、java、python程序员等，家庭角色也可能是是父亲、儿子、
丈夫等，共同构成了社会关系的总和。抽象工厂模式可以理解为简单工厂模式和工厂方法模式的结合体。自然也继承了各自的优缺点。

**类图：**
![](https://md-picture-1257710623.cos.accelerate.myqcloud.com/2023/06/24/16876030182688.jpg)

**代码：**

```go
package main

import "fmt"

type programmer interface {
	writeCode()
}

type javaProgrammer struct {
}

func (j *javaProgrammer) writeCode() {
	fmt.Println("i am  a java programmer,i write java")
}

type goProgrammer struct {
}

func (g *goProgrammer) writeCode() {
	fmt.Println("i am  a golang programmer,i write go")
}

type family interface {
	love()
}

type father struct {
}

func (f *father) love() {
	fmt.Println("i am a father ,i love my wife and my son")
}

type son struct {
}

func (s *son) love() {
	fmt.Println("i am a son ,i love my father and my mother")
}

type programmerFactory struct {
}

func (p *programmerFactory) getProgrammer(programmerType int) programmer {
	switch programmerType {
	case 0:
		return new(javaProgrammer)
	case 1:
		return new(goProgrammer)
	default:
		return nil
	}
}

func (p *programmerFactory) getFamily(roleType int) family {
	return nil
}

type familyFactory struct {
}

func (f *familyFactory) getFamily(roleType int) family {
	switch roleType {
	case 0:
		return new(father)
	case 1:
		return new(son)
	default:
		return nil
	}
}

func (f *familyFactory) getProgrammer(programmerType int) programmer {
	return nil
}

type abstractHumanFactory interface {
	getFamily(roleType int) family
	getProgrammer(programmerType int) programmer
}

type factoryProducer struct {
}

func (*factoryProducer) getFactory(factoryType int) abstractHumanFactory {
	switch factoryType {
	case 0:
		return new(programmerFactory)
	case 1:
		return new(familyFactory)
	default:
		return nil
	}
}

func main() {
	fac := new(factoryProducer)

	programmerFac := fac.getFactory(0)

	java := programmerFac.getProgrammer(0)
	java.writeCode()

	golang := programmerFac.getProgrammer(1)
	golang.writeCode()

	familyFac := fac.getFactory(1)

	f := familyFac.getFamily(0)
	f.love()

	s := familyFac.getFamily(1)
	s.love()
}
```

## 小结

工厂模式作为最简单也最容易理解同时也是日常使用比较多的一个设计模式，大致可分为三种，在日常开发过程中，正确的使用设计模式能够极大的简化我们的代码，降低代码的耦合度，提升可维护性（毕竟是前人经验的总结），但切记千万不能滥用设计模式，使用不当可能会适得其反，千万不要为了使用设计模式而去使用设计模式！！！