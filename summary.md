# ALGO总结

## 题目类型

1. 双指针
2. DP
3. 回溯
4. 贪心:
5. 图论

### 双指针

#### 三数之和

[leetcode链接](https://leetcode.cn/problems/3sum/)

```text
给你一个整数数组 nums ，判断是否存在三元组 [nums[i], nums[j], nums[k]] 满足 i != j、i != k 且 j != k ，同时还满足 nums[i] + nums[j] + nums[k] == 0 。请你返回所有和为 0 且不重复的三元组。

注意：答案中不可以包含重复的三元组。
```

```python
from typing import List

class Solution:
    def threeSum(self, nums: List[int]) -> List[List[int]]:
        # input_data = sorted(nums, key=lambda i: i)
        nums.sort(key = lambda x: x)
        input_data = nums
        input_data_len = len(input_data)

        res = []

        for i in range(input_data_len):
            if i > 0 and input_data[i] == input_data[i - 1]:
                continue
            value1 = input_data[i]
            left_i = i + 1
            right_i = input_data_len - 1

            while left_i < right_i:
                value2 = input_data[left_i]
                value3 = input_data[right_i]
                tmp_result = value1 + value2 + value3

                if tmp_result == 0:
                    if not (res and res[-1][0] == value1 and res[-1][1] == value2 and res[-1][2] == value3):
                        res.append([value1, value2, value3])
                    left_i += 1
                    right_i -= 1
                    continue
                elif tmp_result < 0:
                    left_i += 1
                else:
                    right_i -= 1
        
        return res

if __name__ == '__main__':
    s = Solution()
    res = s.threeSum([-1,0,1,2,-1,-4])
    print(res)
```

### 回溯

#### 电话号码的字母组合

[电话号码的字母组合](https://leetcode.cn/problems/letter-combinations-of-a-phone-number/)

```text
给定一个仅包含数字 2-9 的字符串，返回所有它能表示的字母组合。答案可以按 任意顺序 返回。

给出数字到字母的映射如下（与电话按键相同）。注意 1 不对应任何字母。
```

```python
from typing import List

class Solution:
    key_map = {
        '2': 'abc',
        '3': 'def',
        '4': 'ghi',
        '5': 'jkl',
        '6': 'mno',
        '7': 'pqrs',
        '8': 'tuv',
        '9': 'wxyz'
    }

    @staticmethod
    def get_map(k: str) -> str:
        return Solution.key_map[k]

    def letterCombinations(self, digits: str) -> List[str]:
        solve_list = [ch for ch in digits]
        result = []
        self.backtrace('', solve_list, result, len(solve_list))
        return result
    
    def backtrace(self, tmp_char, remain_list, result, end_len):
        for ch_i in range(len(remain_list)):
            for ch in self.get_map(remain_list[ch_i]):
                tmp_char += ch
                if len(tmp_char) == end_len:
                    result.append(str(tmp_char))
                    tmp_char = str(tmp_char[:-1])
                    continue

                self.backtrace(tmp_char, list(remain_list[ch_i + 1:]), result, end_len)
                tmp_char = str(tmp_char[:-1])


if __name__ == '__main__':
    s = Solution()
    res = s.letterCombinations('23')
    print(res)
```

### 贪心

#### 分发饼干

```text
假设你是一位很棒的家长，想要给你的孩子们一些小饼干。但是，每个孩子最多只能给一块饼干。

对每个孩子 i，都有一个胃口值 g[i]，这是能让孩子们满足胃口的饼干的最小尺寸；并且每块饼干 j，都有一个尺寸 s[j] 。如果 s[j] >= g[i]，我们可以将这个饼干 j 分配给孩子 i ，这个孩子会得到满足。你的目标是满足尽可能多的孩子，并输出这个最大数值。
```

```python
from typing import List

class Solution:
    def findContentChildren(self, g: List[int], s: List[int]) -> int:
        g.sort()
        s.sort()

        cookie_i = 0
        res = 0

        for i in range(len(g)):
            if cookie_i == len(s):
                break
            for cookie in s[cookie_i:]:
                if cookie >= g[i]:
                    res += 1
                    cookie_i += 1
                    break
                cookie_i += 1
        
        return res
    

if __name__ == '__main__':
    s = Solution()
    res = s.findContentChildren([1, 2, 3], [3])
    print(res)
```