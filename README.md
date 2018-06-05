# How to manage data changes in time

Typically, due to two types of reasons, we are using **VALID_FROM_DATE (VFD)** and **VALID_TO_DATE (VTD)** columns for a table

1. Automatically store historical changes in data to see when it has been modified and to look back on past states.

2. Manually adjusting the future change of data to force it be valid or force it to expire at a given time. 

That is, one requirement is important for the past (fact) and the other for the future (plan). 

In **case 1**, only "travelling" in the past can show changes as the present = the future. This is actually a move in the actual state of the database. Modify, delete, insert new data is able only in the present, in real time. Between inserting and deleting a certain data row, there are continuous interval sections to show changes of the relevant data.

In **case 2**, both the past and the future may change. The past can not change here either, because that is a fact and it can have logical implications, but the future is freely editable, because it is only a plan. Only validity interval overlappings are not allowed and the end time of a validity must be higher than its begin time. So, there are only some control rules. 

Sometimes there is a need for a **combination of both**, which requires two validity start-end data pair.   
One refers to case 1, ie what time interval was used / we thought that at interval 2 the attribute value for that business key is this or that. (ie two weeks earlier we thought that  230 HUF would be 1 EUR for the next week, but last week we saw 250 HUF, and now we see 200 HUF.   
On the next week this data will be fact, and will no longer change.)

Extra case: **Time series**. Find here a fast and flexible solution for that.

### See the doc and sql files for more!

