---
description: Asynchronous Programming with Embassy
slug: /lab/04
unlisted: true
---

# 04 - Asynchronous Development

This lab will teach you the principles of asynchronous programming, and its application in Embassy.


## Resources

1. **Bert Peters**, *[How does async Rust work](https://bertptrs.nl/2023/04/27/how-does-async-rust-work.html)* 
2. **Omar Hiari**, *[Sharing Data Among Tasks in Rust Embassy: Synchronization Primitives](https://dev.to/apollolabsbin/sharing-data-among-tasks-in-rust-embassy-synchronization-primitives-59hk)* 

## Asynchronous functions and Tasks

Until now you've only worked with simple (almost) serial programs. However not all programs can be designed to run serially/sequentially. Handling multiple I/O events concurrently usually requires separate parallel tasks. 
Example: Reading a button press while blinking an LED. A single loop would block the button reading event while waiting for the timer to finish.

```mermaid
sequenceDiagram
    participant Button as Button
    participant Timer as Timer
    participant Task as Main Task (LED + Button)
    participant LED as LED Control
    
    loop
    %% LED starts blinking
    Task->>LED: Turn LED ON
    Timer->>+Task: Delay 1 sec (Blocks everything)
    
    %% Button presses button during delay
    Button-->>Task: Button Press Sent (but microcontroller is busy)
 
    
    Task->>-Task: Continue with next instruction
    %% LED continues
    Task->>LED: Turn LED OFF

    Timer->>+Task: Delay 1 sec (Blocks everything)
    Button-->>Task:Button Press Sent (but microcontroller is busy)

    Task->>-Task: Continue with next instruction

    %% Now the task checks the button, but it's too late

    Task->>Button: Check if button is pressed
    Button-->>Task: No press detected (press was missed)
    end
    
    Note over Button, Button: User pressed button, but MCU was busy!
    Note over Task: Button check happens too late.


```

 To address this issue, we would need to spawn a new task in which we would wait for the button press, while blinking the LED in the `main` function. 

When thinking of how exactly this works, you would probably think that the task is running on a separate *thread* than the `main` function. Usually this would be the case when developing a normal computer application. Multithreading is possible, but requires a preemptive operating system. Without one, only one thread can independently run per processor core and that means that, since we are using only one core of the RP2350 (which actually has only 2), we would only be able to run **one thread at a time**. So how exactly does the task wait for the button press in parallel with the LED blinking? 
Short answer is: it doesn't. In reality, both functions run asynchronously. 

A task in Embassy is represented by an *asynchronous function*. Asynchronous functions are different from normal functions, in the sense that they allow asynchronous code execution. Let's take an example from the previous lab:
```rust
#[embassy_executor::task]
async fn button_pressed(mut led: Output<'static, PIN_X>, mut button: Input<'static, PIN_X>) {
    loop {
	info!("waiting for button press");
        button.wait_for_falling_edge().await;
    }
}

#[embassy_executor::main]
async fn main(spawner: Spawner) {
    let peripherals = embassy_rp::init(Default::default());

    let button = Input::new(peripherals.PIN_X, Pull::Up);
    let led2 = Output::new(peripherals.PIN_X, Level::Low);

    spawner.spawn(button_pressed(led2, button)).unwrap();

    let mut led = Output::new(peripherals.PIN_X, Level::Low);

    loop {
        led.toggle();
        Timer::after_millis(200).await;
    }
}
```
In this example, we notice that both the `button_pressed` and `main` functions are declared as `async`, telling the compiler to treat them as asynchronous functions. Inside the `main` function (which is also a task, actually), we blink the LED:

```rust
loop {
    led.toggle();

    Timer::after_millis(200).await;
}
```

## `await` keyword

After setting the timer, our `main` function would need to wait until the alarm fires after 200 ms. Instead of just waiting and blocking the current and *only* thread of execution, it could allow the thread to do another action in the meantime. This is where the `.await` keyword comes into play.
When using `.await` inside of an asynchronous function, we are telling a third party (called the **executor**, detailed later) that this action might take more time to finish, so *do something else* until it's ready. Basically, the execution flow of the asynchronous function function is halted exactly where `.await` is used, and the executor starts running another task. In our case, it would halt the main function while waiting for the alarm to go off and it could start running the code inside the `button_pressed` task.
```rust
loop {
    info!("waiting for button press");
    button.wait_for_falling_edge().await;
}
```
We can see that here, we also use the `wait_for_falling_edge` function asynchronously, meaning that until we get a signal that a button has been pressed, the executor can decide to do other stuff. If it has nothing else to do, it goes to sleep, until it receives a signal that either the button has been pressed, or the timer has run out. Then, it will resume execution of the function where the action has completed. 
When the button is pressed the execution flow will resume inside of the `button_pressed` task, until it is interrupted by the next `.await` in that function. If the timer runs out before the `button_pressed` task execution reaches the next `.await`, the resuming of the `main` function will delayed until the `button_pressed` task `.await`s.
This method of development allows our programs to run seemingly "in parallel", without the need of multiple threads. Each task *voluntarily* pauses its execution and passes control over to whatever other task needs it. This means that it's the task's business to allow other tasks to run while it's idly waiting for something to happen on its end.
:::note
On a preemptive operating system, it would be the scheduler's job to decide when and for how long processes get to run.
:::

## `Future`s

Rust has a special datatype that represents an action that will complete sometime in the future. By using `.await` on a `Future`, we are passing control to another task until the `Future` completes.
:::info
In the `button_pressed` task, the `wait_for_falling_edge` returns a `Future`, which is then `.await`ed.
:::
This is a simplified version of what a `Future` in Rust really looks like:
```rust
enum Poll<T> {
    Pending,
    Ready(T),
}

trait Future {
   type Output;
   fn poll(&mut self) -> Poll<Self::Output>;
}
```
The `Future` has an `Output` associated type, that represents the type of the result that it will return once it completes. For `wait_for_falling_edge()`, the Output type is `()` (nothing).
The function `poll` returns a `Poll` type, which can either be `Pending`, or `Ready<T>` (T will be output in this case).
Let's break down what all of this means. A `Future` needs to be checked on, every now and then, to see what its status is. This is the job of the **Executor**. The executor must regularly ask the `Future` if it's completed, or if it needs more time before it can give a result. We can say that the `Future` is `poll`ed, and depending on whether it's ready to give a result or not, it gives its status as `Pending` or `Ready`. If it's still pending, it needs more time before it can return a result, so the executor moves on to poll another `Future`. Whenever the `Future` is completed, it returns `Ready` once polled, and the executor returns execution back to the function where the `Future` `.await`ed.

```mermaid
sequenceDiagram
    autonumber
    Executor->>+Future: poll()
    loop until the Future finishes all the requests to the Hardware
        Future->>+Hardware: execute_next_action()
        Hardware-->>Future: in_progress()
        note right of Hardware: performs the action in parallel
        Future-->>-Executor: Poll::Pending
        note over Executor: sleeps until an event arrives
        note right of Hardware: sends an event when job is done (interrupt)
        Hardware--)-Executor: event
        Executor->>+Future: poll()
    end
    Future->>Hardware: read_value()
    Hardware-->>Future: value
    Future-->>-Executor: Poll::Ready(value)
```

:::note
An efficient executor will not poll all tasks. Instead, tasks signal the executor that they are ready to make progress by using a `Waker`.
:::

:::info
A real future in Rust looks like this:
```rust
pub trait Future {
    type Output;

    // Required method
    fn poll(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Self::Output>;
}
```
:::

Under the hood, the Rust compiler is actually transforming our asynchronous function into a state-machine. That is why we can only use `.await` inside of an `async` function, because it needs to be treated differently than an ordinary function in order to work asynchronously.

:::info
Asynchronous programming is widely used in web development. In JavaScript, the equivalent of a `Future` would be a `Promise`.
:::

Read more about how async/await works in Rust [here](https://rust-lang.github.io/async-book/01_getting_started/01_chapter.html).

### `await`ing multiple `Future`s

Sometimes we need to `.await` several futures at the same time. Embassy provides two ways of doing this:
- `select` - wait for several `Future`s, stop as soon as **one** of them **returns**;
- `join` - wait for several `Future`s until they **all return**

#### `select`

In some cases, we might find ourselves in the situation where we need to await multiple futures at a time. For example, we want to wait for a button press *and* wait for a timer to expire, and we deal with each future completion in different ways.

There is a function in Embassy that allows us to do this: `select`. It takes two `Future`s as arguments, and polls both of them to see which one completes first.
```rust
let select = select(button.wait_for_falling_edge(), Timer::after_secs(5)).await;
```

It returns an `Either` type, that looks like this:
```rust
pub enum Either<A, B> {
    First(A),
    Second(B),
}
```
A and B are the results of each `Future`, so we can just use a `match` on the `select` variable to see which `Future` finished first.
```rust
match select {
    First(res1) => {
        // handle case for button press
    },
    Second(res2) => {
        // handle case for alarm firing
    }
}
```

:::warning
After selecting the first `Future` that completes, the other one is *dropped*. For instance, if the button press happens first, the timer will be stopped.
:::

:::info
You can also use [`select3`](https://docs.rs/embassy-futures/latest/embassy_futures/select/fn.select3.html), [`select4`](https://docs.rs/embassy-futures/latest/embassy_futures/select/fn.select4.html) or [`select_array`](https://docs.rs/embassy-futures/latest/embassy_futures/select/fn.select_array.html) when dealing with more than two `Future`s.
:::

#### `join`

Similarly, we can also [`join`](https://docs.rs/embassy-futures/latest/embassy_futures/join/fn.join.html) multiple `Future`s, meaning that we wait for all of them to complete before moving on. 

```rust
let (res1, res2) = join(button.wait_for_falling_edge(), Timer::after_secs(5)).await;
```

`join` returns a tuple containing the results of both `Future`s.


## Channels

Up to this point, to be able to share peripherals or data across multiple tasks, we have been using global `Mutex`s or passing them directly as parameters to the tasks. But there are other, more convenient ways to send data to and from tasks. Instead of having to make global, static variables that are shared by tasks, we could choose to only send the information that we need from one task to another. To achieve this, we can use *channels*.

**Channels** allow a unidirectional flow of information between two endpoints: the *Sender* and the *Receiver*. The sender sends a value through the channel, and the receiver receives this value once it is ready to do so. Until it is ready, the data will be stored inside a queue. Channels in Embassy are *Multiple Producer, Multiple Consumer*, which means that we can have a channel associated with multiple senders and multiple receivers. 

To use a channel in Embassy, we first need to declare a static instance of the channel. 

```rust
static CHANNEL: Channel<ThreadModeRawMutex, bool, 64> = Channel::new();
```
- `ThreadModeRawMutex` - the type of Mutex that the Channel internally uses. It is a mutex that can safely be shared between threads
- `bool` - the type of data that is sent through the channel
- `64` - the maximum number of values that can be stored in the channel's queue

Let's say we spawn a task `task1` that runs a timer. Every second, we want to toggle an LED in the `main` function, based on the timer running in `task1`. For this, `task1` would need to send a signal to the `main` program every time the 1 second alarm has fired, meaning the task and the main program would share the channel. `task1` would *send* over the channel, and `main` would *receive*.

Inside `task1`, we would just set a timer and wait until it fires. After it fires, we send a signal through the channel, to indicate that 1 second has elapsed.

```rust
#[embassy_executor::task]
async fn task1() {
    loop {
        Timer::after_secs(1).await;
        CHANNEL.send(true).await;
    }
}
```

In the `main` function, we need to then wait for the signal, and once it's received, toggle the LED.

```rust
// ---- fn main() ----
loop {
    let value = CHANNEL.receive().await;
    match value {
        true => led.toggle().unwrap(),
        false => info!("We got something else")
    }
}
```

:::info
The reason we need all of this is because Rust doesn't allow us to mutably borrow more than once. To use a peripheral (say PWM) inside multiple tasks, 
we would need to either move it inside the task entirely, or use a mutable reference to it. If we have multiple tasks, though, once we move our peripheral variable *inside* the first task,
we can't pass it to another task, because the value was *moved* inside that task completely. And if we wanted to pass it as a mutable reference instead, we would quickly realize that Rust 
doesn't allow multiple mutable references at once, to avoid concurrent modifications. So this is why we need to either declare a global, static `Mutex` that any task can access, to ensure 
that the value cannot be modified concurrently by two different tasks, or use channels and keep the peripheral inside the `main` function.

To better understand the concepts of ownership and borrowing in Rust, take a look at [chapter 4](https://doc.rust-lang.org/book/ch04-00-understanding-ownership.html) of the Rust Book.
:::

### Buzzer

A buzzer is a hardware device that emits sound. There are two types of buzzers:
- *active buzzer* - connected to VCC and GND, with a resistance - emits a constant frequency
- *passive buzzer* - connected to a GPIO pin and GND, with a resistance - frequency can be controlled through the pin with PWM

![Buzzer](images/buzzer.png)

:::tip
To control the buzzer, all you need to do is to set the `top` value of the PWM config to match the frequency you want!
:::

#### How to wire an RGB LED

The buzzer on the development board is connected a pin in the J9 block.

![board_buzzer](./images/board_buzzer.png)

## Exercises

1. Make the 4 LEDs (YELLOW, RED, GREEN, BLUE) blink at different frequencies. Use PWM to change the light intensity smoothly between 0% and 100%. (**2p**)
  Blink:
  - YELLOW -> 3 times/sec
  - RED -> 4 times/sec
  - GREEN -> 5 times/sec
  - BLUE -> 1 time/sec
   :::tip
    Use a different task instance for each LED. You can spawn multiple instances of the same task. Use [`AnyPin`](https://docs.embassy.dev/embassy-rp/git/rp2040/gpio/struct.AnyPin.html) and blinking frequency parameters for the task. 
   :::

2. Change the monochromatic LED's intensity, using switch **SW_4** and switch **SW_5**. **SW_4** will increase the intensity, and button **SW_5** will decrease it. (**2p**)

:::tip
- Use PWM to control the intensity.
- Create two tasks, one for **SW_4**, one for button **SW_5**. Use a channel to send commands from each button task to the main task.
:::

3. Control the speed of the servo motor using the potentiometer. Use button **SW_6** to change the direction in which the motor is spinning. (**2p**)


4. Simulates a traffic light using the RED, YELLOW and GREEN LEDs on the board in the following scenarios: (**2p**)

| Default               | Pedestrian when Green | Pedestrian when Red or Yellow |
| ----------------------| --------------------- | ----------------------------- |
| Green -> 5s           | Yellow Blink -> 1s    |   Keep Red -> +2 s            |
| Yellow Blink -> 1s    | Red -> 4s             |   Reset to Default            |
| Red -> 2s             | Reset to Default      |                               |
| Reset                 |                       |                               |

Use the "**Pedestrian when Green**" and "**Pedestrian when Red or Yellow**" if the word "pedestrian" was written over serial using **UART** .

:::info
The UART (Universal Asynchronous Receiver-Transmitter) peripheral is a hardware module inside a microcontroller that enables serial communication between devices without needing an external clock signal. 
The RP2350 has two UART peripherals . The lab board's debugger chip is uses UART0: Pin GP0 (transmit - TX pin) and pin GP1 (receive -RX pin ) for serial communication.

To read input over serial using UART you can use :

```rust
bind_interrupts!(struct Irqs {
    UART0_IRQ => BufferedInterruptHandler<UART0>;
});


let (tx_pin, rx_pin, uart) = (p.PIN_0, p.PIN_1, p.UART0);

static TX_BUF: StaticCell<[u8; 16]> = StaticCell::new();
let tx_buf = &mut TX_BUF.init([0; 16])[..];
static RX_BUF: StaticCell<[u8; 16]> = StaticCell::new();
let rx_buf = &mut RX_BUF.init([0; 16])[..];
let uart = BufferedUart::new(uart, Irqs, tx_pin, rx_pin, tx_buf, rx_buf, Config::default());
let (mut tx, rx) = uart.split();


info!("Reading...");
loop {
    let mut buf = [0; 31];
    let _ = rx.read_exact(&mut buf).await;

    info!("RX {:?}", buf);
}

```
To write to serial you need to open the serial monitor tab in Visual Studio Code. 
![serial_monitor](./images/serial_monitor.png)

:::

:::tip
Use a separate task for the timer, LEDs and serial read. Use channels to communicate the traffic light states between the tasks.
:::


1. Continue exercise 4, adding a new task to control the buzzer. The buzzer make a continuous low frequency sound while the traffic light is green and yellow and should start beeping on and off while the traffic light is red. (**2p**)


6. Using the previous exercise control the traffic light using two buttons. To trigger the "pedestrian" scenario, both buttons need to be pressed at some point in time. (**0.5p**).

:::tip
Take a look at [join](#join)   
:::