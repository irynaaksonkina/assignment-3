create table customers (
    customer_id serial primary key,
    full_name varchar(100) not null,
    email varchar(100) unique not null,
    balance numeric(10,2) default 0
);

create table products (
    product_id serial primary key,
    product_name varchar(100) not null,
    price numeric(10,2) not null,
    stock_quantity int not null
);

create table orders (
    order_id serial primary key,
    customer_id int references customers(customer_id),
    order_date timestamp default current_timestamp,
    total_amount numeric(10,2) default 0
);

create table order_items (
    order_item_id serial primary key,
    order_id int references orders(order_id),
    product_id int references products(product_id),
    quantity int not null,
    price numeric(10,2) not null
);

create table order_log (
    log_id serial primary key,
    order_id int,
    customer_id int,
    action varchar(50),
    log_date timestamp default current_timestamp
);


-- 1

create or replace function calculate_order_total(p_order_id int)
returns numeric(10,2)
language plpgsql
as $$
declare
    v_total numeric(10,2);
begin
    select coalesce(sum(quantity * price), 0)
    into v_total
    from order_items
    where order_id = p_order_id;

    return v_total;
end;
$$;


-- 2

create or replace procedure create_order(p_customer_id int)
language plpgsql
as $$
declare
    v_exists int;
begin
    select count(*)
    into v_exists
    from customers
    where customer_id = p_customer_id;

    if v_exists = 0 then
        raise exception 'customer not found';
    end if;

    insert into orders (customer_id, total_amount, order_date)
    values (p_customer_id, 0, current_timestamp);
end;
$$;


-- 3

create or replace procedure add_product_to_order(
    p_order_id int,
    p_product_id int,
    p_quantity int
)
language plpgsql
as $$
declare
    v_stock int;
    v_price numeric(10,2);
begin
    if p_quantity <= 0 then
        raise exception 'quantity must be greater than zero';
    end if;

    select stock_quantity, price
    into v_stock, v_price
    from products
    where product_id = p_product_id;

    if not found then
        raise exception 'product not found';
    end if;

    if v_stock < p_quantity then
        raise exception 'not enough stock';
    end if;

    insert into order_items (order_id, product_id, quantity, price)
    values (p_order_id, p_product_id, p_quantity, v_price);

    update products
    set stock_quantity = stock_quantity - p_quantity
    where product_id = p_product_id;
end;
$$;


-- 4

create or replace function trg_update_order_total()
returns trigger
language plpgsql
as $$
declare
    v_order_id int;
begin
    if tg_op = 'DELETE' then
        v_order_id := old.order_id;
    else
        v_order_id := new.order_id;
    end if;

    update orders
    set total_amount = calculate_order_total(v_order_id)
    where order_id = v_order_id;

    return null;
end;
$$;

create trigger trg_order_items_total
after insert or update or delete on order_items
for each row
execute function trg_update_order_total();


-- 5

create or replace function trg_log_order_created()
returns trigger
language plpgsql
as $$
begin
    insert into order_log (order_id, customer_id, action, log_date)
    values (new.order_id, new.customer_id, 'ORDER_CREATED', current_timestamp);

    return new;
end;
$$;

create trigger trg_orders_audit
after insert on orders
for each row
execute function trg_log_order_created();


-- 6

insert into customers (full_name, email, balance) values
    ('John Smith', 'john.smith@example.com', 150.00),
    ('Anna Brown', 'anna.brown@example.com', 300.00),
    ('Michael Johnson', 'michael.johnson@example.com', 75.50),
    ('Kate Wilson', 'kate.wilson@example.com', 500.00);

insert into products (product_name, price, stock_quantity) values
    ('Laptop', 1200.00, 10),
    ('Mouse', 25.00, 100),
    ('Keyboard', 70.00, 50),
    ('Monitor', 250.00, 20),
    ('USB-C Cable', 15.00, 200);

call create_order(1);
call create_order(2);
call create_order(3);

call add_product_to_order(1, 1, 1);
call add_product_to_order(1, 2, 2);
call add_product_to_order(2, 3, 1);
call add_product_to_order(2, 5, 3);
call add_product_to_order(3, 4, 2);

select o.order_id, c.full_name, o.total_amount
from orders o
join customers c on c.customer_id = o.customer_id;

select product_id, product_name, stock_quantity
from products
order by product_id;

select * from order_log;

do $$
begin
    call create_order(999);
exception
    when others then
        raise notice 'error: %', sqlerrm;
end;
$$;

do $$
begin
    call add_product_to_order(1, 2, 0);
exception
    when others then
        raise notice 'error: %', sqlerrm;
end;
$$;

do $$
begin
    call add_product_to_order(1, 1, 9999);
exception
    when others then
        raise notice 'error: %', sqlerrm;
end;
$$;


-- bonus

explain analyze
select
    oi.order_id,
    p.product_name,
    oi.quantity,
    oi.price,
    oi.quantity * oi.price as item_total
from order_items oi
join products p on oi.product_id = p.product_id
where oi.order_id = 1;