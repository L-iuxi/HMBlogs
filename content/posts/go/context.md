# context
context实际上是一个接口，提供了四种方法 `Done()`,`Deadline()`,`Err()`,`Value()`，可以在一个请求链路中，优雅地传递取消信号，超时，和截止日期，并且携带一些范围内的键值对数据

context主要解决三个问题：超时取消，请求信号传播，请求级数据传递
- 当超时发生时，所有子操作都会收到通知，立刻退出
- 可以传递请求级的原数据，比如用户id等
## 查找
context的查找是链式的，当前层级没有需要的key，就调用parent.Value()继续往上查找，这个过程会一直递归直到找到对应的key或者返回nil

## 取消
context的取消主要是通过channel关闭实现的，有三种方法
- 超时取消：调用定时器，超时自动cancel
- 主动取消：创建的时候返回一个cancel函数，调用就会关闭done channel，所有的调用这个context的groutine都可以通过done方法获得通知
- 级联取消：父context被取消的时候，下面的所有子context也会被取消
# interface
interface包括动态类型和动态值
eface是不带方法的interface得实现，包含数据指针和类型指针
```bash
type eface struct {
    _type *_type
    data  unsafe.Pointer
}
```
iface是带接口的interface实现
```bash
type iface struct {
    tab  *itab
    data unsafe.Pointer
}
```
包含itab和data，itab存储了接口类型，具体类型，方法表，方法表是个函数指针数组，保存了该实现方法所有接口方法的地址

## 类型转换和类型断言的区别
类型转换：T(Value)是在编译期确定的强制转换，转换前后的✌️类型要互相兼容
类型断言：Value.(T)是运行期的动态检查，从接口中提取具体类型

- 类型转换在编译期保证成功，而类型断言在编译期有可能失败
- 类型转换底层是简单的数据结构转换，而类型断言涉及到底层接口类型
- 使用场景不同，类型转换用户字符串，数字之间互相转换，类型断言用于接口编程

应用
- 依赖注入：通过定义接口抽象，让高层代码不依赖具体实现
- 类型断言和反射配合使用：orm