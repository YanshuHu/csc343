CSC343 A2

*TO DO*


1. Months
SET search_path TO uber,public;
SELECT client.client_id, client.email,
    COUNT(distinct to_char(request.datetime, 'YYYY-MM')) AS months
FROM client INNER JOIN request
    ON client.client_id = request.client_id
    RIGHT JOIN  dropoff
    ON request.request_id = dropoff.request_id
GROUP BY client.client_id
ORDER BY COUNT(distinct to_char(request.datetime, 'YYYY-MM')) DESC;


2. Lure them back
SET search_path TO uber, public;
SELECT  client_id,
    	concat_ws(' ', firstname::text, surname::text) as name,
    	CASE WHEN email IS NULL THEN 'unknown' ELSE email END,
    	before_2014_sum as billed,
    	(rides_2014 - rides_2015) as decline

    	FROM
        	(SELECT DISTINCT *,

        	(SELECT SUM(b.amount)
        	FROM request r RIGHT JOIN billed b
            	ON r.request_id = b.request_id
        	WHERE date_part('year', r.datetime) < 2014
            	AND r.client_id = c.client_id
        	GROUP BY c.client_id) as before_2014_sum,

        	(SELECT COUNT(r.request_id)
        	FROM request r RIGHT JOIN billed b
            	ON r.request_id = b.request_id
        	WHERE date_part('year', r.datetime) = 2014
            	AND r.client_id = c.client_id
        	GROUP BY c.client_id) as rides_2014,

        	(SELECT COUNT(r.request_id)
            	FROM request r RIGHT JOIN billed b
                	ON r.request_id = b.request_id
            	WHERE date_part('year', r.datetime) = 2015
                	AND r.client_id = c.client_id
            	GROUP BY c.client_id) as rides_2015

        	FROM client c) as a

    	WHERE before_2014_sum > 500
   		 AND rides_2014 > 0
   		 AND rides_2014 < 11
   		 AND rides_2015 < rides_2014;



3.
SET search_path TO uber, public;
CREATE VIEW dropoff_pickup as
select dispatch.driver_id ,dropoff.request_id,
dropoff.datetime as dropoff_date, pickup.datetime as pickup_date
from dropoff
inner join pickup on dropoff.request_id = pickup.request_id
inner join dispatch on dispatch.request_id = dropoff.request_id;

CREATE VIEW duration as
select SUM(dropoff_pickup.dropoff_date - dropoff_pickup.pickup_date)
as duration, driver_id,
to_char(dropoff_pickup.dropoff_date, 'YYYY-MM-DD') as date from
dropoff_pickup
group by to_char(dropoff_pickup.dropoff_date, 'YYYY-MM-DD'),
driver_id;


CREATE VIEW duration2 as
select a.driver_id, a.date as first_day, a.duration as
first_duration,
b.date as second_day, b.duration as second_duration,
c.date as third_day, c.duration as third_duration from
duration as a, duration as b, duration as c
where a.driver_id = b.driver_id and a.driver_id = c.driver_id and
a.date::date = b.date::date - interval '1' day
and a.date::date = c.date::date - interval '2' day and
a.duration > '12 hours' and b.duration > '12 hours'
and c.duration > '12 hours';


CREATE VIEW break as
select MIN(b.pickup_date - a.dropoff_date)
as break, a.request_id as dropoff_request_id from
dropoff_pickup as a, dropoff_pickup as b
where to_char(a.dropoff_date, 'YYYY-MM-DD') =
to_char(b.pickup_date, 'YYYY-MM-DD')
and (a.dropoff_date <= b.pickup_date)
and a.request_id != b.request_id
and a.driver_id = b.driver_id
group by a.request_id;


CREATE VIEW break_driver as
select break, driver_id, to_char(dropoff.datetime, 'YYYY-MM-DD')
as date from
break inner join dropoff
on dropoff.request_id = break.dropoff_request_id
inner join dispatch on
dropoff.request_id = dispatch.request_id;


CREATE VIEW break_15less as
select break, driver_id,
to_char(dropoff.datetime, 'YYYY-MM-DD') as date from
break inner join dropoff
on dropoff.request_id = break.dropoff_request_id
inner join dispatch on
dropoff.request_id = dispatch.request_id
where break <= '15 minutes';

select
duration2.driver_id as driver, duration2.first_day as start,
duration2.first_duration +
duration2.second_duration + duration2.third_duration as driving,
break_driver.break + a.break + b.break as breaks
from
duration2 left join break_driver
on duration2.driver_id = break_driver.driver_id
and duration2.first_day = break_driver.date
left join break_driver as a
on duration2.driver_id = a.driver_id
and duration2.second_day = a.date
left join break_driver as b
on duration2.driver_id = b.driver_id
and duration2.third_day = b.date
inner join break_15less
on duration2.driver_id = break_15less.driver_id;

DROP VIEW dropoff_pickup;
DROP VIEW duration;
DROP VIEW duration2;
DROP VIEW break;
DROP VIEW break_driver;
DROP VIEW break_15less;






4. Do drivers improve?


SET search_path TO uber, public;
CREATE VIEW qualified_drivers as
select dispatch.driver_id,
date(date_trunc('day', min(request.datetime)) + '4 days') as fifth
from dropoff
inner join request
on request.request_id = dropoff.request_id
inner join dispatch
on dispatch.request_id = dropoff.request_id
group by dispatch.driver_id
having count(distinct to_char(request.datetime, 'YYYY-MM-DD')) > 1;

-- drivers before 5th day
CREATE VIEW before_fifth as
select qualified_drivers.driver_id, avg(rating)
from qualified_drivers
inner join dispatch
on dispatch.driver_id = qualified_drivers.driver_id
inner join dropoff
on dropoff.request_id = dispatch.request_id
inner join request
on request.request_id = dropoff.request_id
inner join driverrating
on driverrating.request_id = dropoff.request_id
where
request.datetime < qualified_drivers.fifth
group by qualified_drivers.driver_id;

-- ratings after 5th day
CREATE VIEW after_fifth as
select qualified_drivers.driver_id, avg(rating)
from qualified_drivers
inner join dispatch
on dispatch.driver_id = qualified_drivers.driver_id
inner join dropoff
on dropoff.request_id = dispatch.request_id
inner join request
on request.request_id = dropoff.request_id
inner join driverrating
on driverrating.request_id = dropoff.request_id
where
request.datetime > qualified_drivers.fifth
group by qualified_drivers.driver_id;

select trained as type, count(driver.driver_id),
avg(before_fifth.avg) as early, avg(after_fifth.avg) as late from
before_fifth full outer join after_fifth
on before_fifth.driver_id = after_fifth.driver_id
left join driver on before_fifth.driver_id = driver.driver_id
or after_fifth.driver_id = driver.driver_id
group by trained
order by type ASC;

DROP VIEW qualified_drivers;
DROP VIEW before_fifth;
DROP VIEW after_fifth;





5. Bigger and smaller spenders
SET search_path TO uber, public;

CREATE VIEW billed_clients AS
select sum.client_id, sum.month, sum.sum, avg.avg,
CASE WHEN (sum.sum - avg.avg) >= 0
THEN 'at or above' ELSE 'below' END as comparison FROM

(select concat(EXTRACT(year from request.datetime),' ',
 EXTRACT(month from request.datetime)) as month,
avg(amount)
from request right join dropoff
on request.request_id = dropoff.request_id
left join billed on dropoff.request_id = billed.request_id
group by concat(EXTRACT(year from request.datetime),' ',
 EXTRACT(month from request.datetime))) as avg

right join

(select sum(amount), concat(EXTRACT(year from request.datetime),' ',
 EXTRACT(month from request.datetime))
as month, request.client_id
from request right join dropoff
on request.request_id = dropoff.request_id
left join billed on dropoff.request_id = billed.request_id
group by concat(EXTRACT(year from request.datetime),' ',
 EXTRACT(month from request.datetime)),
request.client_id) as sum

on avg.month = sum.month;

CREATE VIEW all_clients AS
select concat(EXTRACT(year from request.datetime),' ',
 EXTRACT(month from request.datetime)) as date,
client.client_id
from request, client
group by concat(EXTRACT(year from request.datetime),' ',
 EXTRACT(month from request.datetime)), client.client_id
order by client.client_id;

select all_clients.client_id as client_id,
all_clients.date as month,
CASE WHEN billed_clients.sum IS NULL
THEN '0' ELSE billed_clients.sum END as total,
CASE WHEN (billed_clients.sum - billed_clients.avg) >= 0
THEN 'at or above' ELSE 'below' END as comparison
FROM billed_clients RIGHT JOIN all_clients
ON billed_clients.month = all_clients.date
AND billed_clients.client_id = all_clients.client_id
ORDER BY month ASC, total ASC, client_id ASC;

DROP VIEW billed_clients;
DROP VIEW all_clients;



*client_id and month is a key*
6. Frequent riders

SET search_path TO uber, public;


create view initial_rides as
select client_id,
    to_char(request.datetime, 'YYYY') as year,
    count(client_id) as rides
	from dropoff inner join request
	on request.request_id = dropoff.request_id
	group by client_id, to_char(request.datetime, 'YYYY');

create view all_clients as
select client.client_id, to_char(dropoff.datetime, 'YYYY') as year
from client, request
right join dropoff
on request.request_id = dropoff.request_id;

CREATE view rides_user_year as
select a.client_id, a.year,
CASE WHEN rides is NULL then 0
      WHEN rides is NOT NULL then rides
   	 END as rides
from a left join initial_rides
on a.client_id = initial_rides.client_id
 and a.year = initial_rides.year;

-- Highest
create view highest as
select MAX(rides) as rides FROM
rides_user_year;

-- Second
create view second_highest as
SELECT MAX(rides) as second_rides
FROM rides_user_year
where rides not in (select * from highest);

CREATE VIEW third_highest as
SELECT MAX(rides) as third_rides
FROM rides_user_year
WHERE rides not in (select * from second_highest)
and (rides not in (select * from highest));

create view lowest as
select MIN(rides) as rides FROM
rides_user_year;

create view second_lowest as
SELECT MIN(rides) as second_rides
FROM rides_user_year
where rides not in (select * from lowest);


CREATE VIEW third_lowest as
SELECT MIN(rides) as third_rides
FROM rides_user_year
WHERE rides not in (select * from second_lowest)
and (rides not in (select * from lowest));

select distinct * from rides_user_year
where rides = (select * from lowest)
or rides = (select * from second_lowest)
or rides = (select * from third_lowest)
	or rides = (select * from highest)
	or rides = (select * from second_highest)
	or rides = (select * from third_highest)
ORDER BY rides DESC, year ASC;





7. Ratings histogram
select DISTINCT driver.driver_id, r5, r4, r3, r2, r1, r0 FROM

 (select driver_id from driver) as driver
 inner join

 (select driver_id, count(driverrating.rating) as r5
 from driverrating left outer join dispatch on driverrating.request_id = dispatch.request_id
 where driverrating.rating = 5
 group by driver_id) as r5
 on driver.driver_id = r5.driver_id
 left outer join

 (select driver_id, count(driverrating.rating) as r4
 from driverrating left outer join dispatch on driverrating.request_id = dispatch.request_id
 where driverrating.rating = 4
 group by driver_id) as r4
 on driver.driver_id = r4.driver_id
 left outer join

 (select driver_id, count(driverrating.rating) as r3
 from driverrating left outer join dispatch on driverrating.request_id = dispatch.request_id
 where driverrating.rating = 3
 group by driver_id) as r3
 on driver.driver_id = r3.driver_id
 left outer join

 (select driver_id, count(driverrating.rating) as r2
 from driverrating left outer join dispatch on driverrating.request_id = dispatch.request_id
 where driverrating.rating = 2
 group by driver_id) as r2
 on driver.driver_id = r2.driver_id
 left outer join

 (select driver_id, count(driverrating.rating) as r1
 from driverrating left outer join dispatch on driverrating.request_id = dispatch.request_id
 where driverrating.rating = 1
 group by driver_id) as r1
 on driver.driver_id = r1.driver_id
 left outer join

 (select driver_id, count(driverrating.rating) as r0
 from driverrating left outer join dispatch on driverrating.request_id = dispatch.request_id
 where driverrating.rating = 0
 group by driver_id) as r0
 on driver.driver_id = r0.driver_id

 order by r5 DESC, r4 DESC, r3 DESC, r2 DESC, r1 DESC, r0 DESC;

8. Scarching backs?

select request.client_id, avg(driverrating.rating) - avg(clientrating.rating) as difference, count(clientrating.rating) from
clientrating left join driverrating
on clientrating.request_id = driverrating.request_id
left join request
on clientrating.request_id = request.request_id
group by request.client_id
order by difference asc;

9. Consistent raters

select distinct raters.client_id, client.email from

	(select request.client_id from
	request left join dispatch
	on request.request_id = dispatch.request_id
	left join driverrating
	on driverrating.request_id = request.request_id
	group by dispatch.driver_id, request.client_id
	having request.client_id not in

	(select request.client_id from
	request left join dispatch
	on request.request_id = dispatch.request_id
	left join driverrating
	on driverrating.request_id = request.request_id
	group by request.client_id, dispatch.driver_id
	having count(driverrating) = 0)) as raters

	left join client on raters.client_id = client.client_id
	order by email asc;



10.

SET search_path TO uber, public;
CREATE VIEW source as
select request.request_id, request.datetime, request.source,
place.location as source_location from
request inner join place
on request.source = place.name;

CREATE VIEW destination as
select request.request_id, request.destination,
place.location as destination_location from
request inner join place
on request.destination = place.name;

CREATE VIEW source_destination as
select source.request_id, source.datetime,
 source.source,source.source_location,
   	destination.destination, destination.destination_location,
   	dispatch.driver_id, billed.amount
from
source
inner join
destination
on source.request_id = destination.request_id
inner join
dropoff
on dropoff.request_id = source.request_id
inner join
dispatch
on dispatch.request_id = source.request_id
left join
billed
on source.request_id = billed.request_id;

CREATE VIEW twentyfourteen as
select SUM(source_location <@> destination_location)
as mileage_2014, SUM(amount) as billings_2014, driver_id,
to_char(datetime, 'MM') as month
from source_destination
where to_char(datetime, 'YYYY') = '2014'
group by to_char(datetime, 'MM'), driver_id;

CREATE VIEW twentyfifteen as
select SUM(source_location <@> destination_location)
as mileage_2015, SUM(amount) as billings_2015, driver_id,
to_char(datetime, 'MM') as month
from source_destination
where to_char(datetime, 'YYYY') = '2015'
group by to_char(datetime, 'MM'), driver_id;



CREATE VIEW Months as
SELECT
to_char(DATE '2014-01-01' +
(interval '1' month * generate_series(0,11)), 'MM') as mo;


CREATE VIEW mileage_billings as
select driver.driver_id, Months.mo as month,
CASE     WHEN mileage_2014 is not NULL THEN mileage_2014
     WHEN mileage_2014 is NULL THEN 0 end as mileage_2014,
CASE     WHEN billings_2014 is not NULL THEN billings_2014
     WHEN billings_2014 is NULL THEN 0 end as billings_2014,
CASE     WHEN mileage_2015 is not NULL THEN mileage_2015
     WHEN mileage_2015 is NULL THEN 0 end as mileage_2015,
CASE     WHEN billings_2015 is not NULL THEN billings_2015
     WHEN billings_2015 is NULL THEN 0 end as  billings_2015,
CASE
    WHEN billings_2014 IS NULL and billings_2015 is not null
   	 THEN billings_2015
    WHEN billings_2014 IS not NULL and billings_2015 is null
   	 THEN - billings_2014
    WHEN billings_2014 is not null and billings_2015 is not null
   	 THEN billings_2015 - billings_2014 END as billings_increase,
CASE
    WHEN mileage_2014 IS NULL and mileage_2015 is not null
   	 THEN mileage_2015
    WHEN mileage_2014 IS not NULL and mileage_2015 is null
   	 THEN - mileage_2014
    WHEN mileage_2014 is not null and mileage_2015 is not null
   	 THEN mileage_2015 - mileage_2014
   			 END as mileage_increase
FROM
twentyfourteen full outer join twentyfifteen
on twentyfourteen.driver_id = twentyfifteen.driver_id
and twentyfourteen.month = twentyfifteen.month
right join driver
on driver.driver_id = twentyfourteen.driver_id
or driver.driver_id = twentyfifteen.driver_id
inner join Months on twentyfifteen.month = Months.mo
or twentyfourteen.month = Months.mo
order by driver.driver_id ASC, month ASC;

create view all_months as
select driver.driver_id, months.mo from driver, months;

select all_months.driver_id, all_months.mo as month,
CASE     WHEN mileage_2014 is not NULL THEN mileage_2014
     WHEN mileage_2014 is NULL THEN 0 end as mileage_2014,
CASE     WHEN billings_2014 is not NULL THEN billings_2014
     WHEN billings_2014 is NULL THEN 0 end as billings_2014,
CASE     WHEN mileage_2015 is not NULL THEN mileage_2015
     WHEN mileage_2015 is NULL THEN 0 end as mileage_2015,
CASE     WHEN billings_2015 is not NULL THEN billings_2015
     WHEN billings_2015 is NULL THEN 0 end as 	 billings_2015,
CASE
    WHEN billings_2014 IS NULL and billings_2015 is not null
   	 THEN billings_2015
    WHEN billings_2014 IS not NULL and billings_2015 is null
   	 THEN - billings_2014
    WHEN billings_2014 is not null and billings_2015 is not null
   	 THEN billings_2015 - billings_2014
    WHEN billings_2014 IS NULL AND billings_2015 IS NULL THEN 0
    END as billings_increase,
CASE
    WHEN mileage_2014 IS NULL and mileage_2015 is not null
   	 THEN mileage_2015
    WHEN mileage_2014 IS not NULL and mileage_2015 is null
   	 THEN - mileage_2014
    WHEN mileage_2014 is not null and mileage_2015 is not null
   	 THEN mileage_2015 - mileage_2014
    WHEN mileage_2014 IS NULL AND mileage_2015 IS NULL THEN     0
    END as mileage_increase
from all_months left join mileage_billings
on all_months.driver_id = mileage_billings.driver_id
and all_months.mo = mileage_billings.month
order by all_months.driver_id ASC, month ASC;

DROP VIEW mileage_billings;
DROP VIEW all_months;
DROP VIEW Months;
DROP VIEW twentyfifteen;
DROP VIEW twentyfourteen;
DROP VIEW source_destination;
DROP VIEW source;
