---
layout: section
---
# A few things about Rust 

---
layout: two-cols
---

# Variables in Rust: const

### A few characteristics:
- **Usage**: For values known at compile time that will never change;
- **Immutable**: Constants cannot be changed after they are defined.
- **Compile-Time Known**: The value must be known at compile time.
- **Usual Location in Embedded**: Flash / ROM (with the code) - in other words - it is inlined (so no runtime allocation);
- **Naming Convention**: UPPER_SNAKE_CASE


::right::

<br>
<br>
<br>

``` rust 
//EXAMPLES

const MAX_UC_SPEED i16: 150;

const SECONDS_PER_HOUR: u32 = 3600;

const PI_VAL: f32 = 3.14159;

const MAGIC_NUMBER i64: 43248578;


```

---
layout: two-cols
---

# Variables in Rust: let

### A few characteristics:

- **Usage**: For values unknown at compile time that will not change once an initial value is set (for example- values that ar read from a config file at boot time);
- **Immutable by Default**: Variables declared with let are immutable; 
- **Runtime Known**: The value is determined at runtime, usually unknown at compile time; 
- **Usual Location in Embedded**: Stored in SRAM (RAM) since it's allocated at runtime.
- **Naming Convention**: snake_case

::right::

<br>
<br>

```rust
//EXAMPLES

let board_id: String = get_board_id(); 

let WiFi_id: String = read_WiFi_id_from_config(); 

let AES_key: [u8; 32] = read_AES_key_from_OTP(); 
// AES-256 key



```

---
layout: two-cols
---

# Variables in Rust: let mut

- **Usage**: For variables holding values that might change during program execution.
- **Mutable**: Variables declared with let mut are mutable and can be reassigned after initialization.
- **Runtime Known**: The value is determined at runtime, usually unknown at compile time; 
- **Usual Location in Embedded**: Stored in SRAM (RAM) because it can change during program execution.
- **Naming Convention**: snake_case 

::right::

<br>
<br>

```rust
//EXAMPLES
let mut signal = read_adc_signal(); 
let mut max_fft_value = get_max_fft_value(&signal);


```

---
layout: two-cols
---

# Variables: Copy in Rust

### A few observations:

- Intuitive and simple for types that implement the `Copy` trait:
- - primitive types: `i32`, `f64`, `bool`, `char`
- - tooples composed of primitive types
- You need to pay attention for types that do not implement the `Copy` trait. E.g.:
- - `String`
- - `Vec <_>`

:: right::

``` rust
//EXAMPLE with int
fn main() {
    let x: i32 = 128;  // `x` is an integer (implements `Copy`)
    let y: i32 = x;  // y copies the value of x
    println!("x = {}, y = {}", x, y);  
// Compiles & prints expected value
}

//EXAMPLE with String
fn main() {
    let wifi_name_1 = String::from("RoEduNet");  
// `wifi_name_1` owns the string
    let wifi_name_2 = wifi_name_1;  
// Ownership moves from `wifi_name_1` to `wifi_name_2`
    println!("{}", wifi_name_2);  
// Compiles & prints expected value
    println!("{}", wifi_name_1);  
// compiler ERROR: value borrowed after move
}

```

---
layout: two-cols
---

# Variables: Solution for copy for String (example)

### A few observations:

- `.clone()` performs a copy of the data
- Unlike a move, both WiFiName_1 and WiFiName_2 remain valid and independent of each other (as expected)
- you can do this on data types that support the `clone` method, e.g.:
- - `String`
- - `Vec <_>`

::right::

```rust 
fn main() {
    let wifi_name_1  = String::from("RoEduNet");
    let wifi_name_2 = wifi_name_1.clone();  
    // Creates a copy (clone) of the string

    println!("wifi_name_1 = {}", wifi_name_1);      
    println!("wifi_name_2 = {}", wifi_name_2);

    // Both lines compiles & print expected value

}
```

---
layout: two-cols
---

# Variables: Simple borrow example

- `&wifi_name_1` creates an immutable reference to wifi_name_1 without transferring ownership.
- Both wifi_name_1 and wifi_name_2 can be used simultaneously.
- Since it's an immutable reference, you cannot modify wifi_name_1 through wifi_name_2.

::right::

```rust

fn main() {
    let wifi_name_1 = String::from("RoEduNet");  
    let wifi_name_2 = &wifi_name_1;  
    // Borrows wifi_name_1 (immutable reference)

    println!("{}", wifi_name_2);  
    println!("{}", wifi_name_1);  
    // Both lines compiles & print expected value
}

fn main() {
    let wifi_name_1 = String::from("RoEduNet");  
    let wifi_name_2 = &wifi_name_1;  
    // Borrows wifi_name_1 (immutable reference)

    wifi_name_2.push_str("edu_roam");
    //compiler error: cannot borrow `*wifi_name_2` 
    //as mutable, as it is behind a `&` reference

    println!("{}", wifi_name_2);  
    println!("{}", wifi_name_1);  
    //code does not compile
}


```

---
layout: two-cols
---

# Variables: How to modify
