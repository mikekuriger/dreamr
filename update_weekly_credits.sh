#!/bin/bash

date=$(date "+%Y-%m-%d %H:%M:00")
mysql -u root -ppay4mysql dreamr -e 'select * from user_credits;'
mysql -u root -ppay4mysql dreamr -e 'update user_credits set text_remaining_week=2,updated_at = NOW();'
mysql -u root -ppay4mysql dreamr -e 'select * from user_credits;'
