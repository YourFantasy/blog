---
weight: 5
title: "Maximum Non-overlapping Intervals"
date: 2023-06-24T12:57:40+08:00
lastmod: 2023-06-24T14:57:40+08:00
draft: false
author: "Bard"
description: "Solving interval merging problem using Greedy algorithm"
images: []
resources:

tags: ["algorithm","greed"]
categories: ["technology"]

lightgallery: true
---

## Problem Description

Given N closed intervals [ai, bi], you need to select a subset of intervals on the number line such that the selected intervals do not overlap with each other (including the endpoints).

Output the maximum number of intervals that can be selected.

Input Format
The first line contains an integer N, representing the number of intervals.

The next N lines contain two integers ai and bi each, representing the endpoints of an interval.

Output Format
Output an integer representing the maximum number of non-overlapping intervals that can be selected.

Constraints
1 ≤ N ≤ 105,
-109 ≤ ai ≤ bi ≤ 109

```markdown
Sample Input:
3
-1 1
2 4
3 5
Sample Output:
2
```

## Code Implementation

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

## Proof

First, sort the original intervals in ascending order of their right endpoints.

For the first interval, select its right endpoint.

Starting from the second interval, check if there is an intersection between the current interval and the previous intervals. If there is an intersection, merge the two intervals (rightPoint is the minimum right endpoint before merging); otherwise, increment the count of non-overlapping intervals.
For the k-th interval, if the current interval does not intersect with any of the previous intervals (if the left endpoint of the current interval is greater than the minimum right endpoint of the previous intervals), increment the count of non-overlapping intervals by 1.