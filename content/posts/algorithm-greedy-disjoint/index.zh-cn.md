---
weight: 5
title: "最大不相交区间数量"
date: 2023-06-24T12:57:40+08:00
lastmod: 2023-06-24T14:57:40+08:00
draft: false
author: "Bard"
description: "贪心算法解决区间合并问题"
images: []
resources:

tags: ["algorithm","greed"]
categories: ["technology"]

lightgallery: true
---

## 题目描述

给定 N个闭区间 [ai,bi]，请你在数轴上选择若干个区间，使得选中的区间之间互不相交（包括端点）。

输出可选取区间的最大数量。

输入格式
第一行包含整数 N
，表示区间数。

接下来 N
 行，每行包含两个整数 ai,bi
，表示一个区间的两个端点。

输出格式
输出一个整数，表示可选取区间的最大数量。

数据范围
1≤N≤105
,
−109≤ai≤bi≤109
```markdown
输入样例：
3
-1 1
2 4
3 5
输出样例：
2
```

## 代码实现

```go
package main

import (
	"bufio"
	"fmt"
	"os"
	"sort"
	"strconv"
	"strings"
)

func main() {
	var n int
	fmt.Scanf("%d", &n)

	scanner := bufio.NewScanner(os.Stdin)
	buf := make([]byte, 2000*1024)
	scanner.Buffer(buf, len(buf))
	points := make([][]int, n)
	for i := 0; i < n; i++ {
		scanner.Scan()
		strList := strings.Split(scanner.Text(), " ")
		a, _ := strconv.Atoi(strList[0])
		b, _ := strconv.Atoi(strList[1])
		points[i] = []int{a, b}
	}
	sort.Slice(points, func(i, j int) bool {
		return points[i][1] < points[j][1]
	})
	cnt := 1
	rightPoint := points[0][1]
	for i := 1; i < n; i++ {
		if points[i][0] > rightPoint {
			cnt++
			rightPoint = points[i][1]
		}
	}
	fmt.Println(cnt)
}

```

## 证明
先把原始区间按照右端点从小到大排序

对于第一个区间，选择右端点

从第二个区间开始，判断两个区间是否有交集，如果有交集，则合并两个区间（rightPoint是合并之前区间内最小右端点）；否则不相交区间+1
对于第k个区间，如果当前区间和前面所有区间（如果当前区间的左端点大于之前区间的最小右端点）都不相交，
不相交区间+1