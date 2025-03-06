--Реализовать хранимую процедуру, которая возвращает текстовую строку с информацией
--о предприятии (идентификатор, название, область, дата, название подстанции и сумма
--к оплате для последнего потребления). Обработать ситуацию, когда предприятие ничего не потребляло.
CREATE OR REPLACE FUNCTION get_last_consumption_info(p_enterprise_id INT)
RETURNS TEXT AS $$
DECLARE
    result TEXT;
BEGIN
    -- Проверяем существование предприятия
    IF NOT EXISTS (SELECT 1 FROM enterprise WHERE id = p_enterprise_id) THEN
        RETURN 'Ошибка: Предприятие с id ' || p_enterprise_id || ' не найдено.';
    END IF;

    SELECT CONCAT(
        'Идентификатор: ', e.id, ', ',
        'Название: ', e.name, ', ',
        'Область: ', e.region, ', ',
        'Дата: ', c.weekday, ', ',
        'Подстанция: ', COALESCE(s.name, 'неизвестно'), ', ',
        'Сумма к оплате: ', COALESCE(c.to_be_paid, 0)
    ) INTO result
    FROM consumption c
    JOIN enterprise e ON c.enterprise_id = e.id
    LEFT JOIN substation s ON c.substation_id = s.id
    WHERE c.enterprise_id = p_enterprise_id
    ORDER BY c.account_number DESC
    LIMIT 1;

    -- Если потребления нет, возвращаем сообщение
    IF result IS NULL THEN
        RETURN 'Предприятие ' || p_enterprise_id || ' не потребляло электроэнергию.';
    END IF;

    RETURN result;
END;
$$ LANGUAGE plpgsql;


--Примеры употребления
SELECT get_last_consumption_info(2);
SELECT get_last_consumption_info(77);


--Добавить таблицу, содержащую списки подстанций, с которыми работают предприятия.
--При вводе потребления проверять, может ли предприятие работать с данной подстанцией.
CREATE TABLE enterprise_substation (
    enterprise_id INT REFERENCES enterprise(id) ON DELETE CASCADE,
    substation_id INT REFERENCES substation(id) ON DELETE CASCADE,
    PRIMARY KEY (enterprise_id, substation_id)
);
-- Заполняем таблицу 
INSERT INTO enterprise_substation (enterprise_id, substation_id) VALUES
(1, 1), (1, 2), (2, 3), (2, 4), (3, 5), (4, 1), (5, 2);

-- Триггер для проверки
CREATE OR REPLACE FUNCTION check_enterprise_substation()
RETURNS TRIGGER AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM enterprise_substation
        WHERE enterprise_id = NEW.enterprise_id AND substation_id = NEW.substation_id
    ) THEN
        RAISE EXCEPTION 'Ошибка: Предприятие % не может работать с подстанцией %', NEW.enterprise_id, NEW.substation_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER check_enterprise_substation_trigger
BEFORE INSERT ON consumption
FOR EACH ROW
EXECUTE FUNCTION check_enterprise_substation();

--Примеры упортебления
INSERT INTO consumption (account_number, weekday, enterprise_id, substation_id, electricity_id, expenditure, to_be_paid, loss_amount)
VALUES (37127, 'Суббота', 1, 1, 1, 100, 700000, 2);

INSERT INTO consumption (account_number, weekday, enterprise_id, substation_id, electricity_id, expenditure, to_be_paid, loss_amount)
VALUES (37128, 'Суббота', 1, 3, 1, 100, 700000, 2);


--Реализовать триггер, который при вводе строки в таблице потребления,
--если стоимость не указана, вычисляет её на основе данных из таблицы "ЭЛЕКТРОЭНЕРГИЯ".
CREATE OR REPLACE FUNCTION calculate_cost()
RETURNS TRIGGER AS $$
DECLARE
    cost NUMERIC(10,2); --Для простоты понимания кода сделаем новую переменную с более понятным названием
BEGIN
    SELECT cost_per_1kw INTO cost FROM electricity WHERE id = NEW.electricity_id;
    -- Проверка существования тарифа на электричество
    IF cost IS NULL THEN
        RAISE EXCEPTION 'Ошибка: Тариф на электричество с id % не найден.', NEW.electricity_id;
    END IF;

    IF NEW.to_be_paid IS NULL THEN
        NEW.to_be_paid := NEW.expenditure * cost;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER calculate_cost_trigger
BEFORE INSERT ON consumption
FOR EACH ROW
EXECUTE FUNCTION calculate_cost();

--Примеры употребления
--Автоматическое вычисление
INSERT INTO consumption (account_number, weekday, enterprise_id, substation_id, electricity_id, expenditure, loss_amount)
VALUES (37129, 'Суббота', 2, 3, 2, 150, 2);
--Указание стоимости вручную
INSERT INTO consumption (account_number, weekday, enterprise_id, substation_id, electricity_id, expenditure, to_be_paid, loss_amount)
VALUES (37130, 'Суббота', 3, 5, 3, 200, 1800000, 2);


--Создать представление, содержащее поля: № и дата потребления,
--название предприятия и подстанции, временной интервал, скидка и стоимость к оплате.
--Обеспечить возможность изменения скидки с пересчетом стоимости.
CREATE VIEW consumption_view AS -- Создание представления 
SELECT
    c.account_number,
    c.weekday,
    e.name AS enterprise_name,
    s.name AS substation_name,
    el.time_period,
    COALESCE(e.sale, 0) AS sale, -- Обрабатываем NULL
    c.to_be_paid * (1 - COALESCE(e.sale, 0) / 100.0) AS cost_with_discount
FROM consumption c
JOIN enterprise e ON c.enterprise_id = e.id
JOIN substation s ON c.substation_id = s.id
JOIN electricity el ON c.electricity_id = el.id;

--Комментарий:
-- Понятнее было бы сделать пересчет не по id, а по name.
-- Но у нас name при создании таблицы не было заявлено как unique.
-- Поэтому мы так сделать не можем. 
CREATE OR REPLACE FUNCTION update_discount(enterprise_id INT, new_discount NUMERIC) -- Функция для изменения скидки
RETURNS VOID AS $$
BEGIN
    -- Проверка на существование предприятия
    IF NOT EXISTS (SELECT 1 FROM enterprise WHERE id = enterprise_id) THEN
        RAISE EXCEPTION 'Ошибка: Предприятие с ID % не найдено.', enterprise_id;
    END IF;
    
    UPDATE enterprise
    SET sale = new_discount
    WHERE id = enterprise_id;
END;
$$ LANGUAGE plpgsql;

--Примеры упортебления view
--SELECT * FROM consumption_view;
SELECT * FROM consumption_view WHERE enterprise_name = 'Авиационный завод';
--Пересчет скидки
SELECT update_discount(1, 10);
SELECT * FROM consumption_view WHERE enterprise_name = 'Авиационный завод';